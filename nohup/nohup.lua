#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd  = require("posix.unistd")
local signal  = require("posix.signal")

if #arg == 0 then
	unistd.write(2, "nohup: missing operand\n")
	os.exit(127)
end

signal.signal(signal.SIGHUP, signal.SIG_IGN)

local rest = {}
for i = 2, #arg do rest[#rest + 1] = arg[i] end
unistd.execp(arg[1], rest)
unistd.write(2, "nohup: " .. arg[1] .. ": No such file or directory\n")
os.exit(127)
