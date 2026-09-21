#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local fcntl = require("posix.fcntl")

local width = 80
local break_spaces = false
local count_bytes = false

local optind = 1
for opt, optarg, oi in unistd.getopt(arg, "bsw:") do
	if opt == "w" then
		width = tonumber(optarg) or 80
	elseif opt == "s" then
		break_spaces = true
	elseif opt == "b" then
		count_bytes = true
	else
		unistd.write(2, "usage: fold [-bs] [-w width] [file...]\n")
		os.exit(2)
	end
	optind = oi
end
if arg[optind] == "--" then optind = optind + 1 end

-- Where a character leaves the cursor. A tab goes to the next multiple
-- of eight, a backspace steps back and a carriage return goes home: fold
-- counts what the terminal would show, and -b counts bytes instead.
local function advance(col, c)
	if count_bytes then return col + 1 end
	if c == "\t" then return col + 8 - (col % 8) end
	if c == "\b" then return col > 0 and col - 1 or 0 end
	if c == "\r" then return 0 end
	return col + 1
end

local function fold_line(line)
	local start, col = 1, 0
	local last_blank = nil
	for i = 1, #line do
		local c = line:sub(i, i)
		local next_col = advance(col, c)
		if next_col > width and i > start then
			-- -s backs up to the last blank, where there is one
			local cut = i - 1
			if break_spaces and last_blank and last_blank >= start then
				cut = last_blank
			end
			unistd.write(1, line:sub(start, cut) .. "\n")
			start = cut + 1
			last_blank = nil
			col = 0
			for n = start, i do col = advance(col, line:sub(n, n)) end
		else
			col = next_col
		end
		if c == " " or c == "\t" then last_blank = i end
	end
	unistd.write(1, line:sub(start) .. "\n")
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
