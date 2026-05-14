#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd   = require("posix.unistd")
local fcntl    = require("posix.fcntl")
local notposix = require("notposix")

local invert = false
local count_only = false
local list_files = false
local line_numbers = false
local ignore_case = false
local quiet = false
local extended = false
local fixed = false
local pattern = nil
local files = {}

local optind = 1
for opt, optarg, oi in unistd.getopt(arg, "EFivclnqe:") do
	if     opt == "E" then extended = true
	elseif opt == "F" then fixed = true
	elseif opt == "i" then ignore_case = true
	elseif opt == "v" then invert = true
	elseif opt == "c" then count_only = true
	elseif opt == "l" then list_files = true
	elseif opt == "n" then line_numbers = true
	elseif opt == "q" then quiet = true
	elseif opt == "e" then pattern = optarg
	end
	optind = oi
end

-- first non-option arg is pattern if not set via -e
if not pattern then
	pattern = arg[optind]
	optind = optind + 1
end

if not pattern then
	unistd.write(2, "grep: missing pattern\n")
	os.exit(2)
end

for i = optind, #arg do files[#files + 1] = arg[i] end

-- compile regex
local re = nil
if not fixed then
	local flags = 0
	if extended then flags = flags | notposix.REG_EXTENDED end
	if ignore_case then flags = flags | notposix.REG_ICASE end
	flags = flags | notposix.REG_NOSUB
	local err
	re, err = notposix.regcomp(pattern, flags)
	if not re then
		unistd.write(2, "grep: " .. (err or "invalid pattern") .. "\n")
		os.exit(2)
	end
end

local function match_line(line)
	if fixed then
		if ignore_case then
			return line:lower():find(pattern:lower(), 1, true) ~= nil
		end
		return line:find(pattern, 1, true) ~= nil
	end
	local m = re:exec(line)
	return m ~= false and m ~= nil
end

local found_any = false
local multi = #files > 1

local function grep_fd(fd, filename)
	local content = ""
	while true do
		local data = unistd.read(fd, 8192)
		if not data or data == "" then break end
		content = content .. data
	end

	local count = 0
	local lineno = 0
	for line in content:gmatch("([^\n]*)\n?") do
		if line == "" and not content:find("\n$") and lineno > 0 then break end
		lineno = lineno + 1
		local m = match_line(line)
		if invert then m = not m end
		if m then
			found_any = true
			count = count + 1
			if quiet then return end
			if list_files then
				unistd.write(1, filename .. "\n")
				return
			end
			if not count_only then
				local prefix = ""
				if multi then prefix = filename .. ":" end
				if line_numbers then prefix = prefix .. lineno .. ":" end
				unistd.write(1, prefix .. line .. "\n")
			end
		end
	end
	if count_only then
		local prefix = multi and (filename .. ":") or ""
		unistd.write(1, prefix .. count .. "\n")
	end
end

if #files == 0 then
	grep_fd(0, "(standard input)")
else
	for _, f in ipairs(files) do
		local fd = fcntl.open(f, fcntl.O_RDONLY)
		if not fd then
			unistd.write(2, "grep: " .. f .. ": No such file or directory\n")
		else
			grep_fd(fd, f)
			unistd.close(fd)
		end
	end
end

if quiet then os.exit(found_any and 0 or 1) end
os.exit(found_any and 0 or 1)
