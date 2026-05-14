#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local fcntl = require("posix.fcntl")

local suppress = {}

local optind = 1
for opt, optarg, oi in unistd.getopt(arg, "123") do
	if opt == "1" then suppress[1] = true
	elseif opt == "2" then suppress[2] = true
	elseif opt == "3" then suppress[3] = true
	end
	optind = oi
end

if #arg - optind + 1 ~= 2 then
	unistd.write(2, "usage: comm [-123] file1 file2\n")
	os.exit(1)
end

local function open_file(path)
	if path == "-" then return 0 end
	local fd = fcntl.open(path, fcntl.O_RDONLY)
	if not fd then
		unistd.write(2, "comm: " .. path .. ": No such file or directory\n")
		os.exit(1)
	end
	return fd
end

local function readline(fd)
	local buf = {}
	while true do
		local ch = unistd.read(fd, 1)
		if not ch or ch == "" then
			if #buf == 0 then return nil end
			return table.concat(buf)
		end
		if ch == "\n" then return table.concat(buf) end
		buf[#buf + 1] = ch
	end
end

local fd1 = open_file(arg[optind])
local fd2 = open_file(arg[optind + 1])

local line1 = readline(fd1)
local line2 = readline(fd2)

local col2 = suppress[1] and "" or "\t"
local col3 = (suppress[1] and "" or "\t") .. (suppress[2] and "" or "\t")

while line1 or line2 do
	if line1 and (not line2 or line1 < line2) then
		if not suppress[1] then unistd.write(1, line1 .. "\n") end
		line1 = readline(fd1)
	elseif line2 and (not line1 or line2 < line1) then
		if not suppress[2] then unistd.write(1, col2 .. line2 .. "\n") end
		line2 = readline(fd2)
	else
		if not suppress[3] then unistd.write(1, col3 .. line1 .. "\n") end
		line1 = readline(fd1)
		line2 = readline(fd2)
	end
end
