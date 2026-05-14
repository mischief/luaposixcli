#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local fcntl = require("posix.fcntl")

if #arg < 2 then
	unistd.write(2, "cmp: missing operand\n")
	os.exit(2)
end

local fd1 = fcntl.open(arg[1], fcntl.O_RDONLY)
local fd2 = fcntl.open(arg[2], fcntl.O_RDONLY)
if not fd1 or not fd2 then
	unistd.write(2, "cmp: cannot open file\n")
	os.exit(2)
end

local byte = 0
local line = 1
while true do
	local c1 = unistd.read(fd1, 1)
	local c2 = unistd.read(fd2, 1)
	if (not c1 or c1 == "") and (not c2 or c2 == "") then
		break
	end
	byte = byte + 1
	if c1 ~= c2 then
		if not c1 or c1 == "" then
			unistd.write(2, "cmp: EOF on " .. arg[1] .. "\n")
		elseif not c2 or c2 == "" then
			unistd.write(2, "cmp: EOF on " .. arg[2] .. "\n")
		else
			unistd.write(1, string.format("%s %s differ: byte %d, line %d\n", arg[1], arg[2], byte, line))
		end
		unistd.close(fd1)
		unistd.close(fd2)
		os.exit(1)
	end
	if c1 == "\n" then
		line = line + 1
	end
end

unistd.close(fd1)
unistd.close(fd2)
os.exit(0)
