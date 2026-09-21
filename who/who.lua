#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
-- who - who is logged in, from the login records
local prefix = ((arg[0] or "who"):match("(.+/)") or "./") .. "../"
package.path = prefix .. "?.lua;" .. prefix .. "share/lua/5.4/?.lua;" .. package.path

local unistd = require("posix.unistd")
local stat = require("posix.sys.stat")
local utmp = require("luaposixcli.utmp")
local util = require("luaposixcli.util")

local header, me_only, count, boot, runlevel, dead = false, false, false, false, false, false
local show_idle = false

local function usage()
	util.die("usage: who [-bdHlmqrsTu] [file | am i]", 2)
end

local optind = 1
for opt, _, oi in unistd.getopt(arg, "bdHlmqrsTu") do
	if opt == "H" then header = true
	elseif opt == "m" then me_only = true
	elseif opt == "q" then count = true
	elseif opt == "b" then boot = true
	elseif opt == "r" then runlevel = true
	elseif opt == "d" then dead = true
	elseif opt == "u" or opt == "T" then show_idle = true
	elseif opt == "l" or opt == "s" then -- login processes, short listing
	else usage() end
	optind = oi
end

-- POSIX gives who two operands: a file to read instead of the login
-- records, or "am i", which is the other way of asking for -m.
local operands = util.operands(arg, optind)
local file = nil
if #operands == 2 and operands[2]:lower() == "i" then
	me_only = true
elseif #operands == 1 then
	file = operands[1]
elseif #operands ~= 0 then
	usage()
end


-- the terminal this is being asked from, which is what -m is about
local function my_line()
	for fd = 0, 2 do
		local name = unistd.ttyname(fd)
		if name then return (name:gsub("^/dev/", "")) end
	end
	return nil
end

local function stamp(when)
	return os.date("%Y-%m-%d %H:%M", when)
end

-- How long the terminal has been quiet, which is what -u asks for: a
-- dot for the last minute, hours and minutes up to a day, "old" past
-- that. A terminal that is not there has no idle time to report.
local function idle_of(line)
	local st = stat.stat("/dev/" .. line)
	if not st then return "  ?" end
	local quiet = os.time() - st.st_mtime
	if quiet < 60 then return "   ." end
	if quiet >= 24 * 60 * 60 then return " old" end
	return string.format("%02d:%02d", quiet // 3600, (quiet % 3600) // 60)
end

local function show(rec)
	local host = rec.host ~= "" and (" (" .. rec.host .. ")") or ""
	if show_idle then
		unistd.write(1, string.format("%-8s %-12s %s %-8s %6d%s\n",
			rec.user, rec.line, stamp(rec.time), idle_of(rec.line),
			rec.pid, host))
	else
		unistd.write(1, string.format("%-8s %-12s %s%s\n",
			rec.user, rec.line, stamp(rec.time), host))
	end
end

if count then
	local names = {}
	for rec in utmp.each(file) do
		if rec.type == utmp.USER_PROCESS then names[#names + 1] = rec.user end
	end
	if #names > 0 then unistd.write(1, table.concat(names, " ") .. "\n") end
	unistd.write(1, "# users=" .. #names .. "\n")
	os.exit(0)
end

if boot then
	for rec in utmp.each(file) do
		if rec.type == utmp.BOOT_TIME then
			unistd.write(1, string.format("%-8s %-12s %s\n",
				"", "system boot", stamp(rec.time)))
		end
	end
	os.exit(0)
end

if runlevel then
	for rec in utmp.each(file) do
		if rec.type == utmp.RUN_LVL then
			unistd.write(1, string.format("%-8s %-12s %s\n",
				"run-level", string.char(rec.pid & 0xff), stamp(rec.time)))
		end
	end
	os.exit(0)
end

if header then
	if show_idle then
		unistd.write(1, string.format("%-8s %-12s %s %6s\n",
			"NAME", "LINE", "TIME", "PID"))
	else
		unistd.write(1, string.format("%-8s %-12s %s\n", "NAME", "LINE", "TIME"))
	end
end

local mine = me_only and my_line() or nil
for rec in utmp.each(file) do
	local want = dead and rec.type == utmp.DEAD_PROCESS
		or (not dead and rec.type == utmp.USER_PROCESS)
	if want and rec.user ~= "" then
		if not me_only or rec.line == mine then show(rec) end
	end
end
