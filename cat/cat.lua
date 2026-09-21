#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local fcntl = require("posix.fcntl")

local number_all, number_nonblank = false, false
local squeeze, show_ends, show_tabs, show_nonprint = false, false, false, false
local optind = 1

for opt, _, oi in unistd.getopt(arg, "benstuvAET") do
	if opt == "b" then number_nonblank = true
	elseif opt == "e" then show_ends = true; show_nonprint = true
	elseif opt == "n" then number_all = true
	elseif opt == "s" then squeeze = true
	elseif opt == "t" then show_tabs = true; show_nonprint = true
	elseif opt == "u" then -- always unbuffered
	elseif opt == "v" then show_nonprint = true
	elseif opt == "A" then show_ends = true; show_tabs = true; show_nonprint = true
	elseif opt == "E" then show_ends = true
	elseif opt == "T" then show_tabs = true
	else
		io.stderr:write("usage: cat [-benstuv] [file...]\n")
		os.exit(2)
	end
	optind = oi
end
if arg[optind] == "--" then optind = optind + 1 end

local plain = not (number_all or number_nonblank or squeeze
	or show_ends or show_tabs or show_nonprint)

local function copy_fd(fd)
	while true do
		local data = unistd.read(fd, 8192)
		if not data or data == "" then break end
		unistd.write(1, data)
	end
end

-- Visible form of a character, as -v describes it
local function visible(c)
	local b = c:byte()
	if b == 9 then return show_tabs and "^I" or c end
	if b == 10 then return c end
	if b < 32 then return "^" .. string.char(b + 64) end
	if b == 127 then return "^?" end
	if b > 127 then return "M-" .. visible(string.char(b - 128)) end
	return c
end

local lineno = 0
local blank_run = 0

local function format_fd(fd)
	local pending = ""
	while true do
		local data = unistd.read(fd, 8192)
		local eof = not data or data == ""
		pending = pending .. (data or "")
		while true do
			local nl = pending:find("\n", 1, true)
			local line, rest
			if nl then
				line, rest = pending:sub(1, nl - 1), pending:sub(nl + 1)
			elseif eof and pending ~= "" then
				line, rest = pending, ""
			else
				break
			end
			pending = rest
			local blank = (line == "")
			blank_run = blank and blank_run + 1 or 0
			if not (squeeze and blank and blank_run > 1) then
				local out = line
				if show_nonprint or show_tabs then
					out = out:gsub(".", visible)
				end
				if show_ends then out = out .. "$" end
				if number_all or (number_nonblank and not blank) then
					lineno = lineno + 1
					out = string.format("%6d\t%s", lineno, out)
				end
				unistd.write(1, out .. (nl and "\n" or ""))
			end
			if not nl then break end
		end
		if eof then break end
	end
end

local function run(fd)
	if plain then copy_fd(fd) else format_fd(fd) end
end

local files = {}
for i = optind, #arg do files[#files + 1] = arg[i] end

if #files == 0 then
	run(0)
else
	for _, path in ipairs(files) do
		if path == "-" then
			run(0)
		else
			local fd, err = fcntl.open(path, fcntl.O_RDONLY)
			if not fd then
				io.stderr:write("cat: " .. path .. ": " .. err .. "\n")
				os.exit(1)
			end
			run(fd)
			unistd.close(fd)
		end
	end
end
