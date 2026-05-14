#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local fcntl = require("posix.fcntl")

if #arg < 2 then
	unistd.write(2, "cp: missing operand\n")
	os.exit(1)
end

local src = arg[1]
local dst = arg[2]

local fd_in = fcntl.open(src, fcntl.O_RDONLY)
if not fd_in then
	unistd.write(2, "cp: " .. src .. ": No such file or directory\n")
	os.exit(1)
end

local fd_out = fcntl.open(dst, fcntl.O_WRONLY + fcntl.O_CREAT + fcntl.O_TRUNC, 438)
if not fd_out then
	unistd.close(fd_in)
	unistd.write(2, "cp: cannot create " .. dst .. "\n")
	os.exit(1)
end

while true do
	local data = unistd.read(fd_in, 8192)
	if not data or data == "" then
		break
	end
	unistd.write(fd_out, data)
end

unistd.close(fd_in)
unistd.close(fd_out)
