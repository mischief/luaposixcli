#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
-- top - the ps table, repainting. q or Escape quits.
local prefix = ((arg[0] or "top"):match("(.+/)") or "./") .. "../"
package.path = prefix .. "?.lua;" .. prefix .. "share/lua/5.4/?.lua;" .. package.path

local unistd = require("posix.unistd")
local poll = require("posix.poll")
local list = require("ps.list")
local terminfo = require("luaposixcli.term")
local util = require("luaposixcli.util")

local die = util.die

local delay, frames = 2, 0

local i = 1
while i <= #arg do
	local a = arg[i]
	local function value()
		local v = a:sub(3)
		if v == "" then
			i = i + 1
			v = arg[i]
		end
		local n = v and tonumber(v)
		if not n or n < 0 then die("usage: top [-d seconds] [-n frames]") end
		return n
	end
	if a:sub(1, 2) == "-d" then delay = value()
	elseif a:sub(1, 2) == "-n" then frames = math.floor(value())
	else die("usage: top [-d seconds] [-n frames]")
	end
	i = i + 1
end

local term = terminfo.new()
if unistd.isatty(1) ~= 1 then die("not a terminal") end

-- raw first: the size query is answered on the input side, and a cooked
-- terminal would echo it and hand it back a line at a time
term:raw()
term:detect_size()
term:hide_cursor()

local function restore()
	term:show_cursor()
	term:restore()
	term:clear()
end

local function loadavg()
	local f = io.open("/proc/loadavg", "r")
	if not f then return nil end
	local line = f:read("*l")
	f:close()
	return line and line:match("^(%S+%s+%S+%s+%S+)")
end

-- One frame, assembled whole and written once: a picture redrawn as a
-- unit should reach the terminal as one write. Each line clears to the
-- end rather than clearing the screen first, which is what stops the
-- flicker between frames.
local function frame()
	local rows, cols = term.rows or 24, term.cols or 80
	local out = {}
	local function put(s) out[#out + 1] = s end

	local procs, err = list.procs()
	if not procs then die(err) end

	local load = loadavg()
	put("\27[H")
	put(#procs .. " processes" .. (load and ("   load average: " .. load) or ""))
	put("\27[K\r\n\27[K\r\n")

	local shown = 2
	local lines = { list.header(true) }
	for _, p in ipairs(procs) do
		lines[#lines + 1] = list.line(p, true)
	end
	for _, line in ipairs(lines) do
		if shown >= rows - 1 then break end
		put(line:sub(1, cols))
		put("\27[K\r\n")
		shown = shown + 1
	end
	for _ = shown, rows - 2 do put("\27[K\r\n") end
	put("q to quit\27[K")

	term:write(table.concat(out))
end

-- A key ends the wait early; nothing typed means the delay elapsed.
local function wait(seconds)
	local ready = poll.poll({ [0] = { events = { IN = true } } },
		math.floor(seconds * 1000))
	if not ready or ready == 0 then return nil end
	return unistd.read(0, 1)
end

-- xpcall so a fault still puts the terminal back: a full-screen program
-- that dies raw leaves the shell unusable.
local n = 0
local ok, err = xpcall(function()
	while true do
		frame()
		n = n + 1
		if frames > 0 and n >= frames then return end
		local key = wait(delay)
		if key == "q" or key == "\27" or key == "" then return end
	end
end, function(e)
	return debug.traceback(tostring(e), 2)
end)

restore()
if not ok then die(tostring(err)) end
