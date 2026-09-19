#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local stat = require("posix.sys.stat")
local unistd = require("posix.unistd")
local dirent = require("posix.dirent")

local SETUID = tonumber("4000", 8)
local SETGID = tonumber("2000", 8)
local STICKY = tonumber("1000", 8)
local ALLBITS = tonumber("7777", 8)
local ANY_EXEC = tonumber("111", 8)

local shift = { u = 6, g = 3, o = 0 }
local special = { u = SETUID, g = SETGID }

local function die(msg)
	unistd.write(2, "chmod: " .. msg .. "\n")
	os.exit(1)
end

local function current_umask()
	local mask = stat.umask(0)
	stat.umask(mask)
	return mask
end

-- Apply one symbolic mode expression to mode. isdir selects the X behavior.
local function apply_symbolic(spec, mode, isdir)
	local mask = current_umask()
	for clause in (spec .. ","):gmatch("([^,]*),") do
		local pos = 1
		local who = clause:match("^([ugoa]*)", pos)
		pos = pos + #who
		local classes = {}
		local use_umask = false
		if who == "" then
			classes, use_umask = { "u", "g", "o" }, true
		else
			local seen = {}
			for c in who:gmatch(".") do
				if c == "a" then
					for _, k in ipairs({ "u", "g", "o" }) do seen[k] = true end
				else
					seen[c] = true
				end
			end
			for _, k in ipairs({ "u", "g", "o" }) do
				if seen[k] then classes[#classes + 1] = k end
			end
		end
		if pos > #clause then die("invalid mode: " .. spec) end
		while pos <= #clause do
			local op = clause:sub(pos, pos)
			if not op:match("[-+=]") then die("invalid mode: " .. spec) end
			pos = pos + 1
			local copy = clause:match("^([ugo])", pos)
			local perms = ""
			if copy then
				pos = pos + 1
			else
				perms = clause:match("^([rwxXst]*)", pos)
				pos = pos + #perms
			end
			if pos <= #clause and not clause:sub(pos, pos):match("[-+=]") then
				die("invalid mode: " .. spec)
			end

			local bits = 0
			if copy then
				local src = (mode >> shift[copy]) & 7
				for _, k in ipairs(classes) do bits = bits | (src << shift[k]) end
			else
				local base = 0
				if perms:find("r", 1, true) then base = base | 4 end
				if perms:find("w", 1, true) then base = base | 2 end
				if perms:find("x", 1, true) then base = base | 1 end
				if perms:find("X", 1, true) and (isdir or (mode & ANY_EXEC) ~= 0) then
					base = base | 1
				end
				for _, k in ipairs(classes) do
					bits = bits | (base << shift[k])
					if perms:find("s", 1, true) and special[k] then
						bits = bits | special[k]
					end
				end
				if perms:find("t", 1, true) then bits = bits | STICKY end
			end
			if use_umask then bits = bits & ~mask end

			if op == "+" then
				mode = mode | bits
			elseif op == "-" then
				mode = mode & ~bits
			else
				local clear = 0
				for _, k in ipairs(classes) do
					clear = clear | (7 << shift[k])
					if special[k] then clear = clear | special[k] end
					if k == "o" then clear = clear | STICKY end
				end
				mode = (mode & ~clear) | bits
			end
		end
	end
	return mode & ALLBITS
end

local recursive = false
local optind = 1
for opt, _, oi in unistd.getopt(arg, "R") do
	if opt == "R" then recursive = true
	else
		unistd.write(2, "usage: chmod [-R] mode file...\n")
		os.exit(2)
	end
	optind = oi
end

local mode_str = arg[optind]
local files = {}
for i = optind + 1, #arg do files[#files + 1] = arg[i] end

if not mode_str or #files == 0 then
	die("missing operand")
end

local octal = mode_str:match("^[0-7]+$") and tonumber(mode_str, 8)
if not octal and not mode_str:match("^[ugoa]*[-+=]") then
	die("invalid mode: " .. mode_str)
end

local status = 0

local function chmod_one(path)
	local st = stat.stat(path)
	if not st then
		unistd.write(2, "chmod: " .. path .. ": cannot stat\n")
		status = 1
		return
	end
	local isdir = stat.S_ISDIR(st.st_mode) ~= 0
	local mode = octal or apply_symbolic(mode_str, st.st_mode & ALLBITS, isdir)
	local ok, err = stat.chmod(path, mode)
	if not ok then
		unistd.write(2, "chmod: " .. path .. ": " .. (err or "failed") .. "\n")
		status = 1
	end
	if recursive and isdir then
		for name in dirent.files(path) do
			if name ~= "." and name ~= ".." then
				chmod_one(path .. "/" .. name)
			end
		end
	end
end

for _, path in ipairs(files) do chmod_one(path) end
os.exit(status)
