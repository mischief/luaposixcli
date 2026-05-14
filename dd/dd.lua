#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local fcntl = require("posix.fcntl")
local sys_time = require("posix.sys.time")

local ifile, ofile = nil, nil
local bs = 512
local count = nil
local skip = 0
local seek = 0

for _, a in ipairs(arg) do
	local k, v = a:match("^(%w+)=(.+)$")
	if k == "if" then
		ifile = v
	elseif k == "of" then
		ofile = v
	elseif k == "bs" then
		bs = tonumber(v)
	elseif k == "count" then
		count = tonumber(v)
	elseif k == "skip" then
		skip = tonumber(v)
	elseif k == "seek" then
		seek = tonumber(v)
	end
end

local fd_in = 0
if ifile then
	fd_in = fcntl.open(ifile, fcntl.O_RDONLY)
	if not fd_in then
		unistd.write(2, "dd: " .. ifile .. ": No such file or directory\n")
		os.exit(1)
	end
end

local fd_out = 1
if ofile then
	fd_out = fcntl.open(ofile, fcntl.O_WRONLY + fcntl.O_CREAT + fcntl.O_TRUNC, 438)
	if not fd_out then
		unistd.write(2, "dd: cannot open " .. ofile .. "\n")
		os.exit(1)
	end
end

-- skip input blocks
for _ = 1, skip do
	unistd.read(fd_in, bs)
end

-- seek output blocks
if seek > 0 then
	unistd.lseek(fd_out, seek * bs, 0)
end

local blocks_in, blocks_out, bytes_total = 0, 0, 0
local n = 0
while true do
	if count and n >= count then
		break
	end
	local data = unistd.read(fd_in, bs)
	if not data or data == "" then
		break
	end
	blocks_in = blocks_in + 1
	unistd.write(fd_out, data)
	blocks_out = blocks_out + 1
	bytes_total = bytes_total + #data
	n = n + 1
end

if ifile then
	unistd.close(fd_in)
end
if ofile then
	unistd.close(fd_out)
end

unistd.write(
	2,
	string.format("%d+0 records in\n%d+0 records out\n%d bytes copied\n", blocks_in, blocks_out, bytes_total)
)
