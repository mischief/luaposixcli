#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local fcntl = require("posix.fcntl")
local signal = require("posix.signal")

local append, ignore = false, false
local optind = 1

for opt, _, oi in unistd.getopt(arg, "ai") do
	if opt == "a" then append = true
	elseif opt == "i" then ignore = true
	else
		unistd.write(2, "usage: tee [-ai] [file...]\n")
		os.exit(2)
	end
	optind = oi
end

-- -i is about the interrupt, which is the only signal tee is told to
-- ignore; the rest still end it
if ignore then signal.signal(signal.SIGINT, signal.SIG_IGN) end

local flags = fcntl.O_WRONLY | fcntl.O_CREAT
	| (append and fcntl.O_APPEND or fcntl.O_TRUNC)

local status = 0
local fds = {}
for i = optind, #arg do
	local path = arg[i]
	local fd, err = fcntl.open(path, flags, tonumber("644", 8))
	if not fd then
		unistd.write(2, "tee: " .. (err or path .. ": cannot open") .. "\n")
		status = 1
	else
		fds[#fds + 1] = fd
	end
end

while true do
	local data = unistd.read(0, 8192)
	if not data or data == "" then break end
	unistd.write(1, data)
	for _, fd in ipairs(fds) do
		unistd.write(fd, data)
	end
end

for _, fd in ipairs(fds) do unistd.close(fd) end
os.exit(status)
