#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local fcntl = require("posix.fcntl")

local flags = fcntl.O_WRONLY + fcntl.O_CREAT + fcntl.O_TRUNC
local fds = {}
for _, path in ipairs(arg) do
	local fd, err = fcntl.open(path, flags, 420) -- 0644
	if not fd then
		io.stderr:write("tee: " .. path .. ": " .. err .. "\n")
		os.exit(1)
	end
	fds[#fds + 1] = fd
end

while true do
	local data = unistd.read(0, 8192)
	if not data or data == "" then
		break
	end
	unistd.write(1, data)
	for _, fd in ipairs(fds) do
		unistd.write(fd, data)
	end
end

for _, fd in ipairs(fds) do
	unistd.close(fd)
end
