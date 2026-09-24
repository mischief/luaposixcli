#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
-- resize - ask the terminal how big it is and tell the kernel
local prefix = ((arg[0] or "resize"):match("(.+/)") or "./") .. "../"
package.path = prefix .. "?.lua;" .. prefix .. "share/lua/5.4/?.lua;" .. package.path
if not package.cpath:find("build") then
	package.cpath = prefix .. "build/?.so;" .. prefix .. "lib/lua/5.4/?.so;" .. package.cpath
end

local fcntl = require("posix.fcntl")
local termio = require("posix.termio")
local unistd = require("posix.unistd")
local sys = require("luaposixcli.sys")

local function die(msg)
	unistd.write(2, "resize: " .. msg .. "\n")
	os.exit(1)
end

local usage = "usage: resize [-s rows cols] [-u|-c]\n"

local rows, cols, shell
local args = {}
for i = 1, #arg do args[i] = arg[i] end
local i = 1
while args[i] do
	local a = args[i]
	if a == "-s" then
		rows = tonumber(args[i + 1]) or die("-s needs rows and columns")
		cols = tonumber(args[i + 2]) or die("-s needs rows and columns")
		i = i + 2
	elseif a == "-u" then shell = "sh"
	elseif a == "-c" then shell = "csh"
	elseif a == "-h" then unistd.write(1, usage); os.exit(0)
	else unistd.write(2, usage); os.exit(2) end
	i = i + 1
end

-- The terminal is the one to ask and to tell, so it is opened rather
-- than taken from the standard descriptors, which may be redirected.
local fd = fcntl.open("/dev/tty", fcntl.O_RDWR)
if not fd then die("/dev/tty: cannot open") end

-- Put the cursor where no terminal is bigger, ask where it landed, and
-- put it back. The answer is the size.
local function ask()
	local saved = termio.tcgetattr(fd)
	if not saved then die("not a terminal") end
	local raw = termio.tcgetattr(fd)
	raw.lflag = raw.lflag & ~(termio.ICANON | termio.ECHO)
	raw.cc[termio.VMIN] = 0
	raw.cc[termio.VTIME] = 5
	termio.tcsetattr(fd, termio.TCSANOW, raw)

	unistd.write(fd, "\27[s\27[999;999H\27[6n")
	local buf = ""
	while not buf:find("R") do
		local c = unistd.read(fd, 16)
		if not c or #c == 0 then break end
		buf = buf .. c
	end
	unistd.write(fd, "\27[u")
	termio.tcsetattr(fd, termio.TCSANOW, saved)

	local r, c = buf:match("%[(%d+);(%d+)R")
	if not r then die("the terminal did not answer") end
	return tonumber(r), tonumber(c)
end

if not rows then rows, cols = ask() end
if rows < 1 or cols < 1 then die("the terminal answered " .. rows .. "x" .. cols) end

local ok, err = sys.setwinsize(fd, rows, cols)
if not ok then die("cannot set the window size: " .. tostring(err)) end

if shell == "csh" then
	unistd.write(1, ("set noglob;\nsetenv LINES %d;\nsetenv COLUMNS %d;\nunset noglob;\n")
		:format(rows, cols))
else
	unistd.write(1, ("LINES=%d; COLUMNS=%d; export LINES COLUMNS\n")
		:format(rows, cols))
end
