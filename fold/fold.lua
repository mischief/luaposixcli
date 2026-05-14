#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local fcntl = require("posix.fcntl")

local width = 80
local break_spaces = false

local optind = 1
for opt, optarg, oi in unistd.getopt(arg, "bsw:") do
	if opt == "w" then
		width = tonumber(optarg) or 80
	elseif opt == "s" then
		break_spaces = true
	end
	optind = oi
end

local function fold_line(line)
	if #line <= width then
		unistd.write(1, line .. "\n")
		return
	end
	local pos = 1
	while pos <= #line do
		if pos + width - 1 >= #line then
			unistd.write(1, line:sub(pos) .. "\n")
			break
		end
		local chunk = line:sub(pos, pos + width - 1)
		if break_spaces then
			local bp = chunk:match(".*()%s")
			if bp and bp > 1 then
				unistd.write(1, line:sub(pos, pos + bp - 1) .. "\n")
				pos = pos + bp
			else
				unistd.write(1, chunk .. "\n")
				pos = pos + width
			end
		else
			unistd.write(1, chunk .. "\n")
			pos = pos + width
		end
	end
end

local function process(fd)
	local buf = {}
	while true do
		local ch = unistd.read(fd, 4096)
		if not ch or ch == "" then
			if #buf > 0 then fold_line(table.concat(buf)) end
			return
		end
		for i = 1, #ch do
			local c = ch:sub(i, i)
			if c == "\n" then
				fold_line(table.concat(buf))
				buf = {}
			else
				buf[#buf + 1] = c
			end
		end
	end
end

if optind > #arg then
	process(0)
else
	for i = optind, #arg do
		if arg[i] == "-" then
			process(0)
		else
			local fd = fcntl.open(arg[i], fcntl.O_RDONLY)
			if not fd then
				unistd.write(2, "fold: " .. arg[i] .. ": No such file or directory\n")
				os.exit(1)
			end
			process(fd)
			unistd.close(fd)
		end
	end
end
