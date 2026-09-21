#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")

local utc = false
local fmt = nil
local set = nil

local function usage()
	unistd.write(2, "usage: date [-u] [+format]\n")
	os.exit(2)
end

local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "--" then
		fmt = arg[i + 1] and arg[i + 1]:match("^%+(.*)$") or fmt
		break
	elseif a:sub(1, 1) == "+" then
		fmt = a:sub(2)
	elseif a:sub(1, 1) == "-" and #a > 1 then
		for c in a:sub(2):gmatch(".") do
			if c == "u" then utc = true
			elseif c == "s" then
				i = i + 1
				set = arg[i] or usage()
			else usage() end
		end
	else
		usage()
	end
	i = i + 1
end

if set then
	unistd.write(2, "date: setting the clock is not implemented\n")
	os.exit(1)
end

fmt = fmt or "%a %b %e %H:%M:%S %Z %Y"
-- os.date reads the leading ! as "in UTC", which is what -u asks for.
-- The C library calls that zone GMT; every date prints it as UTC.
if utc then fmt = fmt:gsub("%%Z", "UTC") end
unistd.write(1, os.date((utc and "!" or "") .. fmt) .. "\n")
