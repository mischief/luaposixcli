#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
-- rz - receive files over ZMODEM from the other end of this terminal.
--
-- The name is the interface: a ZMODEM sender writes "rz\r" before its
-- first header, so a shell that finds this in PATH completes the
-- handshake with nothing typed here.
local prefix = ((arg[0] or "rz"):match("(.+/)") or "./") .. "../"
package.path = prefix .. "?.lua;" .. prefix .. "share/lua/5.4/?.lua;" .. package.path

local unistd = require("posix.unistd")
local poll = require("posix.poll")
local time = require("posix.time")
local zmodem = require("luaposixcli.zmodem")
local term = require("luaposixcli.term")
local util = require("luaposixcli.util")

if unistd.isatty(0) ~= 1 then
	util.die("not a terminal", 1)
end

local dir = arg[1]
local open_file = nil

-- A sink rather than a data field: the receiver never rewinds, so bytes
-- reach the file as they arrive and no whole file is ever resident.
-- The name comes from the far end, so it is a basename and nothing else;
-- a sender offering ../etc/passwd is asking to write outside the
-- directory it was pointed at.
local function sink(info)
	local name = util.basename(info.name or "")
	if name == "" or name == "." or name == ".." then
		error("rz: the sender offered no usable name", 0)
	end
	local path = dir and (dir .. "/" .. name) or name
	local f, err = io.open(path, "wb")
	if not f then
		error("rz: " .. (err or (path .. ": cannot write")), 0)
	end
	open_file = f
	return {
		write = function(off, data)
			f:seek("set", off)
			f:write(data)
			return true
		end,
		close = function()
			f:close()
			open_file = nil
			return true
		end,
	}
end

local function now()
	local ts = time.clock_gettime(time.CLOCK_MONOTONIC)
	return ts.tv_sec * 1000 + ts.tv_nsec // 1000000
end

local line = {
	now = now,
	write = function(data)
		local off = 1
		while off <= #data do
			local n = unistd.write(1, data:sub(off))
			if not n or n <= 0 then error("rz: write failed", 0) end
			off = off + n
		end
	end,
	read = function(ms)
		local ready = poll.poll({ [0] = { events = { IN = true } } },
			ms and math.max(math.floor(ms), 1) or 1000)
		if not ready or ready == 0 then return nil end
		local data = unistd.read(0, 512)
		if not data or data == "" then return nil end
		return data
	end,
}

local tty = term.new()
tty:raw()

local m = zmodem.receiver({ sink = sink, idle = 15000 })
local ok, res, err = pcall(zmodem.drive, m, line)

tty:restore()
if open_file then open_file:close() end

if not ok then res, err = nil, tostring(res) end
if not res then util.die(tostring(err)) end

for _, f in ipairs(res) do
	io.stderr:write(string.format("%s\t%d bytes\n", f.name, f.received or f.size or 0))
end
