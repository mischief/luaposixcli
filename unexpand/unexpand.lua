#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local fcntl = require("posix.fcntl")

local tabstop = 8
local all = false

local optind = 1
for opt, optarg, oi in unistd.getopt(arg, "at:") do
	if opt == "t" then
		tabstop = tonumber(optarg) or 8
		all = true
	elseif opt == "a" then
		all = true
	end
	optind = oi
end

local function unexpand_line(line)
	local out = {}
	local col = 0
	local i = 1
	local leading = true
	while i <= #line do
		if line:sub(i, i) == " " and (leading or all) then
			local j = i
			while j <= #line and line:sub(j, j) == " " do
				j = j + 1
			end
			local end_col = col + (j - i)
			local pos = col
			while pos < end_col do
				local next_stop = tabstop - (pos % tabstop)
				if pos + next_stop <= end_col then
					out[#out + 1] = "\t"
					pos = pos + next_stop
				else
					out[#out + 1] = string.rep(" ", end_col - pos)
					pos = end_col
				end
			end
			col = end_col
			i = j
		else
			if line:sub(i, i) ~= " " then leading = false end
			out[#out + 1] = line:sub(i, i)
			col = col + 1
			i = i + 1
		end
	end
	return table.concat(out)
end

local function process(fd)
	local buf = {}
	while true do
		local data = unistd.read(fd, 4096)
		if not data or data == "" then
			if #buf > 0 then unistd.write(1, unexpand_line(table.concat(buf)) .. "\n") end
			return
		end
		for i = 1, #data do
			local c = data:sub(i, i)
			if c == "\n" then
				unistd.write(1, unexpand_line(table.concat(buf)) .. "\n")
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
				unistd.write(2, "unexpand: " .. arg[i] .. ": No such file or directory\n")
				os.exit(1)
			end
			process(fd)
			unistd.close(fd)
		end
	end
end
