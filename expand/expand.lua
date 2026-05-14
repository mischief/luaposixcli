#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local fcntl = require("posix.fcntl")

local tabstops = { 8 }

local optind = 1
for opt, optarg, oi in unistd.getopt(arg, "t:") do
	if opt == "t" then
		tabstops = {}
		for n in optarg:gmatch("%d+") do
			tabstops[#tabstops + 1] = tonumber(n)
		end
		if #tabstops == 0 then tabstops = { 8 } end
	end
	optind = oi
end

local function next_tab(col)
	if #tabstops == 1 then
		local ts = tabstops[1]
		return ts - (col % ts)
	end
	for _, stop in ipairs(tabstops) do
		if stop > col then return stop - col end
	end
	return 1
end

local function process(fd)
	local buf = {}
	while true do
		local data = unistd.read(fd, 4096)
		if not data or data == "" then
			if #buf > 0 then unistd.write(1, table.concat(buf)) end
			return
		end
		local col = 0
		for i = 1, #data do
			local c = data:sub(i, i)
			if c == "\t" then
				local spaces = next_tab(col)
				buf[#buf + 1] = string.rep(" ", spaces)
				col = col + spaces
			elseif c == "\n" then
				buf[#buf + 1] = c
				col = 0
			else
				buf[#buf + 1] = c
				col = col + 1
			end
		end
		unistd.write(1, table.concat(buf))
		buf = {}
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
				unistd.write(2, "expand: " .. arg[i] .. ": No such file or directory\n")
				os.exit(1)
			end
			process(fd)
			unistd.close(fd)
		end
	end
end
