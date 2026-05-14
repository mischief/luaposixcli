#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local fcntl = require("posix.fcntl")

local delimiters = "\t"
local serial = false

local optind = 1
for opt, optarg, oi in unistd.getopt(arg, "sd:") do
	if opt == "d" then
		delimiters = optarg
	elseif opt == "s" then
		serial = true
	end
	optind = oi
end

local files = {}
for i = optind, #arg do
	if arg[i] == "-" then
		files[#files + 1] = { fd = 0, done = false }
	else
		local fd = fcntl.open(arg[i], fcntl.O_RDONLY)
		if not fd then
			unistd.write(2, "paste: " .. arg[i] .. ": No such file or directory\n")
			os.exit(1)
		end
		files[#files + 1] = { fd = fd, done = false }
	end
end
if #files == 0 then
	files[1] = { fd = 0, done = false }
end

-- read one line from fd, return nil on EOF
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

local function get_delim(n)
	if #delimiters == 0 then return "" end
	local idx = ((n - 1) % #delimiters) + 1
	local c = delimiters:sub(idx, idx)
	if c == "\\" and idx < #delimiters then
		local nc = delimiters:sub(idx + 1, idx + 1)
		if nc == "n" then return "\n"
		elseif nc == "t" then return "\t"
		elseif nc == "\\" then return "\\"
		elseif nc == "0" then return ""
		end
	end
	return c
end

if serial then
	for _, f in ipairs(files) do
		local first = true
		local di = 1
		while true do
			local line = readline(f.fd)
			if not line then break end
			if not first then
				unistd.write(1, get_delim(di))
				di = di + 1
			end
			unistd.write(1, line)
			first = false
		end
		unistd.write(1, "\n")
		if f.fd ~= 0 then unistd.close(f.fd) end
	end
else
	while true do
		local all_done = true
		local out = {}
		for i, f in ipairs(files) do
			if i > 1 then out[#out + 1] = get_delim(i - 1) end
			if not f.done then
				local line = readline(f.fd)
				if line then
					out[#out + 1] = line
					all_done = false
				else
					f.done = true
					out[#out + 1] = ""
				end
			else
				out[#out + 1] = ""
			end
		end
		if all_done then break end
		unistd.write(1, table.concat(out) .. "\n")
	end
end
