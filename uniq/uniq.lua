#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local fcntl = require("posix.fcntl")

local count_mode = false
local dup_only = false
local uniq_only = false
local files = {}

for _, a in ipairs(arg) do
	if a == "-c" then
		count_mode = true
	elseif a == "-d" then
		dup_only = true
	elseif a == "-u" then
		uniq_only = true
	else
		files[#files + 1] = a
	end
end

local fd = 0
if #files > 0 and files[1] ~= "-" then
	fd = fcntl.open(files[1], fcntl.O_RDONLY)
	if not fd then
		unistd.write(2, "uniq: " .. files[1] .. ": No such file or directory\n")
		os.exit(1)
	end
end

local content = ""
while true do
	local data = unistd.read(fd, 8192)
	if not data or data == "" then
		break
	end
	content = content .. data
end
if fd ~= 0 then
	unistd.close(fd)
end

local function output(line, cnt)
	if dup_only and cnt < 2 then
		return
	end
	if uniq_only and cnt > 1 then
		return
	end
	if count_mode then
		unistd.write(1, string.format("%7d %s\n", cnt, line))
	else
		unistd.write(1, line .. "\n")
	end
end

local prev = nil
local cnt = 0
for line in content:gmatch("([^\n]*)\n?") do
	if line == "" and content:sub(-1) ~= "\n" and prev ~= nil then
		break
	end
	if line == prev then
		cnt = cnt + 1
	else
		if prev ~= nil then
			output(prev, cnt)
		end
		prev = line
		cnt = 1
	end
end
if prev ~= nil then
	output(prev, cnt)
end
