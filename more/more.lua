#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
-- more - show text a screenful at a time.
--
-- The text comes from the files or from a pipe, so the keyboard is
-- /dev/tty and not standard input: a pager reading its own input for
-- keystrokes would eat the text it is meant to be showing.
local prefix = ((arg[0] or "more"):match("(.+/)") or "./") .. "../"
package.path = prefix .. "?.lua;" .. prefix .. "share/lua/5.4/?.lua;" .. package.path
if not package.cpath:find("build") then
	package.cpath = prefix .. "build/?.so;" .. prefix .. "lib/lua/5.4/?.so;" .. package.cpath
end

local unistd = require("posix.unistd")
local fcntl = require("posix.fcntl")
local termio = require("posix.termio")
local sys = require("luaposixcli.sys")
local util = require("luaposixcli.util")

local files = {}
local start_line = 1
local squeeze = false

local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "--" then
		for j = i + 1, #arg do files[#files + 1] = arg[j] end
		break
	elseif a:match("^%+%d+$") then
		start_line = tonumber(a:sub(2))
	elseif a == "-s" then
		squeeze = true
	elseif a:sub(1, 1) == "-" and #a > 1 then
		util.die("usage: more [-s] [+line] [file...]")
	else
		files[#files + 1] = a
	end
	i = i + 1
end

local text = {}
if #files == 0 then
	text[1] = util.slurp_fd(0) or ""
else
	for _, path in ipairs(files) do
		local data, err = util.slurp(path)
		if not data then
			util.warn(err or (path .. ": cannot read"))
		else
			if #files > 1 then
				text[#text + 1] = "::::::::::::::\n" .. path .. "\n::::::::::::::\n"
			end
			text[#text + 1] = data
		end
	end
end

local lines = {}
for line in util.lines(table.concat(text)) do
	if not (squeeze and line == "" and lines[#lines] == "") then
		lines[#lines + 1] = line
	end
end

local first = math.max(1, math.min(start_line, #lines + 1))

local function pour()
	for n = first, #lines do unistd.write(1, lines[n] .. "\n") end
	os.exit(0)
end

-- Not a terminal: a pager is then just cat, which is what makes
-- "cmd | more | grep x" behave. The same goes for a terminal we cannot
-- reach for keystrokes.
if unistd.isatty(1) ~= 1 then pour() end

local tty = fcntl.open("/dev/tty", fcntl.O_RDWR)
if not tty then pour() end

local rows = select(1, sys.winsize(1)) or tonumber(os.getenv("LINES")) or 24
if rows < 2 then rows = 24 end
local page = rows - 1

local saved = termio.tcgetattr(tty)
local function raw()
	if not saved then return end
	local attrs = {}
	for k, v in pairs(saved) do attrs[k] = v end
	attrs.lflag = attrs.lflag & ~(termio.ICANON | termio.ECHO)
	attrs.cc[termio.VMIN] = 1
	attrs.cc[termio.VTIME] = 0
	termio.tcsetattr(tty, termio.TCSANOW, attrs)
end
local function restore()
	if saved then termio.tcsetattr(tty, termio.TCSANOW, saved) end
end

local at = first

local function show(n)
	for _ = 1, n do
		if at > #lines then return false end
		unistd.write(1, lines[at] .. "\n")
		at = at + 1
	end
	return true
end

raw()
show(page)
while at <= #lines do
	local percent = math.floor((at - 1) * 100 / #lines)
	unistd.write(1, "--More--(" .. percent .. "%)")
	local key = unistd.read(tty, 1)
	unistd.write(1, "\r\27[K")
	if key == nil or key == "" or key == "q" or key == "Q" then
		break
	elseif key == " " then
		show(page)
	elseif key == "\n" or key == "\r" then
		show(1)
	elseif key == "b" then
		at = math.max(1, at - 2 * page)
		show(page)
	end
end
restore()
unistd.close(tty)
