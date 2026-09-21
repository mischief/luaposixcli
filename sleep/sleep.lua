#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")

-- POSIX sleep has no options, so anything that looks like one is an
-- error rather than an operand.
if #arg ~= 1 or arg[1]:sub(1, 1) == "-" then
	unistd.write(2, "usage: sleep seconds\n")
	os.exit(2)
end

local seconds = tonumber(arg[1])
if not seconds or seconds < 0 then
	unistd.write(2, "sleep: " .. arg[1] .. ": bad number of seconds\n")
	os.exit(2)
end

local whole = math.floor(seconds)
if whole > 0 then unistd.sleep(whole) end
local rest = seconds - whole
if rest > 0 then
	local time = require("posix.time")
	time.nanosleep({ tv_sec = 0, tv_nsec = math.floor(rest * 1e9) })
end
