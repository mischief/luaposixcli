#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local utsname = require("posix.sys.utsname")
local unistd = require("posix.unistd")

local u = utsname.uname()
local out = {}
local opts = arg[1] or "-s"
if opts == "-a" then
	opts = "-snrvm"
end
for c in opts:gmatch(".") do
	if c == "s" then
		out[#out + 1] = u.sysname
	elseif c == "n" then
		out[#out + 1] = u.nodename
	elseif c == "r" then
		out[#out + 1] = u.release
	elseif c == "v" then
		out[#out + 1] = u.version
	elseif c == "m" then
		out[#out + 1] = u.machine
	end
end
unistd.write(1, table.concat(out, " ") .. "\n")
