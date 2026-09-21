#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local prefix = ((arg[0] or "date"):match("(.+/)") or "./") .. "../"
package.path = prefix .. "?.lua;" .. prefix .. "share/lua/5.4/?.lua;" .. package.path
if not package.cpath:find("build") then
	package.cpath = prefix .. "build/?.so;" .. prefix .. "lib/lua/5.4/?.so;" .. package.cpath
end

local unistd = require("posix.unistd")
local ptime = require("posix.time")
local sys = require("luaposixcli.sys")
local util = require("luaposixcli.util")

local utc = false
local fmt = nil
local set = nil

local function usage()
	util.die("usage: date [-u] [+format]\n" ..
		"       date [-u] mmddhhmm[[cc]yy][.ss]", 2)
end

local optind = 1
for opt, optarg, oi in unistd.getopt(arg, "us:") do
	if opt == "u" then utc = true
	elseif opt == "s" then set = optarg
	else usage() end
	optind = oi
end
local operands = util.operands(arg, optind)

for _, a in ipairs(operands) do
	if a:sub(1, 1) == "+" then
		fmt = a:sub(2)
	elseif not set then
		set = a
	else
		usage()
	end
end

-- The time POSIX writes as mmddhhmm[[cc]yy][.ss]. A year of two digits
-- is this century for 69 and under, the last one above it, which is
-- what POSIX says and what every date does.
local function parse_time(text)
	local body, seconds = text:match("^(%d+)%.(%d%d)$")
	body = body or text:match("^(%d+)$") or usage()
	seconds = tonumber(seconds) or 0

	local month = tonumber(body:sub(1, 2)) or usage()
	local day = tonumber(body:sub(3, 4)) or usage()
	local hour = tonumber(body:sub(5, 6)) or usage()
	local minute = tonumber(body:sub(7, 8)) or usage()
	local now = os.date(utc and "!*t" or "*t")
	local year = now.year

	if #body == 10 then
		local two = tonumber(body:sub(9, 10))
		year = two <= 68 and (2000 + two) or (1900 + two)
	elseif #body == 12 then
		year = tonumber(body:sub(9, 12))
	elseif #body ~= 8 then
		usage()
	end

	-- mktime takes a month of 13 to mean January of the next year. A
	-- date says so instead.
	if month < 1 or month > 12 or day < 1 or day > 31
		or hour > 23 or minute > 59 or seconds > 60 then
		util.die("bad date: " .. text)
	end

	-- mktime reads the local zone. -u asks for UTC, and the difference
	-- between the two is what the same fields mean in each.
	local tm = { tm_year = year - 1900, tm_mon = month - 1, tm_mday = day,
		tm_hour = hour, tm_min = minute, tm_sec = seconds, tm_isdst = -1 }
	local when = ptime.mktime(tm)
	if not when then util.die("bad date: " .. text) end
	-- mktime rolls a day the month does not have into the next month,
	-- which would make the 30th of February a date
	local back = os.date("*t", when)
	if back.day ~= day or back.month ~= month then
		util.die("bad date: " .. text)
	end
	if utc then
		-- the UTC fields carry isdst false; dropping it lets mktime work
		-- the flag out for that date, or the answer is an hour out all
		-- summer
		local there = os.date("!*t", when)
		there.isdst = nil
		when = when + (when - os.time(there))
	end
	return when
end

if set then
	local when = parse_time(set)
	local ok, err = sys.settime(when)
	if not ok then util.die(tostring(err)) end
end

fmt = fmt or "%a %b %e %H:%M:%S %Z %Y"
-- os.date reads the leading ! as "in UTC", which is what -u asks for.
-- The C library calls that zone GMT; every date prints it as UTC.
if utc then fmt = fmt:gsub("%%Z", "UTC") end
unistd.write(1, os.date((utc and "!" or "") .. fmt) .. "\n")
