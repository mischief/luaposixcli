#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")

local month, year
if #arg == 0 then
	local t = os.date("*t")
	month, year = t.month, t.year
elseif #arg == 1 then
	year = tonumber(arg[1])
	month = nil -- full year not implemented, show current month of that year
	local t = os.date("*t")
	month = t.month
elseif #arg >= 2 then
	month = tonumber(arg[1])
	year = tonumber(arg[2])
end

if not month or not year or month < 1 or month > 12 then
	unistd.write(2, "cal: invalid arguments\n")
	os.exit(1)
end

local names = {
	"January",
	"February",
	"March",
	"April",
	"May",
	"June",
	"July",
	"August",
	"September",
	"October",
	"November",
	"December",
}

-- day of week for first of month (0=Sunday)
local function first_dow(y, m)
	local t = os.time({ year = y, month = m, day = 1 })
	return tonumber(os.date("%w", t))
end

-- days in month
local function days_in(y, m)
	if m == 12 then
		return 31
	end
	local t1 = os.time({ year = y, month = m, day = 1 })
	local t2 = os.time({ year = y, month = m + 1, day = 1 })
	return math.floor((t2 - t1) / 86400)
end

-- header
local title = string.format("%s %d", names[month], year)
local pad = math.floor((20 - #title) / 2)
local out = string.format("%-20s\n", string.rep(" ", pad) .. title)
out = out .. "Su Mo Tu We Th Fr Sa\n"

-- body
local dow = first_dow(year, month)
local ndays = days_in(year, month)
local line = string.rep("   ", dow)
for d = 1, ndays do
	line = line .. string.format("%2d", d)
	dow = dow + 1
	if dow == 7 then
		out = out .. line .. "\n"
		line = ""
		dow = 0
	else
		line = line .. " "
	end
end
if #line > 0 then
	out = out .. line .. string.rep(" ", 20 - #line) .. "\n"
end

unistd.write(1, out)
