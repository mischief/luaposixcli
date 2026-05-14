#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local fcntl = require("posix.fcntl")
local utime = require("posix.utime")

for _, path in ipairs(arg) do
	-- create if doesn't exist
	if unistd.access(path, "f") ~= 0 then
		local fd = fcntl.open(path, fcntl.O_WRONLY + fcntl.O_CREAT, 438)
		if fd then
			unistd.close(fd)
		end
	end
	-- update timestamps to now
	utime.utime(path)
end
