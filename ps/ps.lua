#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local pwd = require("posix.pwd")
local ps_sys = require("ps.sys")

local all = false
local full = false

for _, a in ipairs(arg) do
	for i = 2, #a do
		local c = a:sub(i, i)
		if c == "A" or c == "e" then all = true
		elseif c == "f" then full = true
		end
	end
end

local myuid = unistd.getuid()

local procs = ps_sys.getprocs()
if not procs then
	io.stderr:write("ps: cannot get process list\n")
	os.exit(1)
end

-- Sort by pid
table.sort(procs, function(a, b) return a.pid < b.pid end)

-- Format tty number
local function fmt_tty(tty_nr)
	if tty_nr == 0 or tty_nr == -1 then return "?" end
	local major = (tty_nr >> 8) & 0xff
	local minor = tty_nr & 0xff
	if major == 136 then return "pts/" .. minor end
	return tostring(tty_nr)
end

-- Header
if full then
	unistd.write(1, string.format("%-8s %5s %5s %-5s %s\n", "UID", "PID", "PPID", "TTY", "CMD"))
else
	unistd.write(1, string.format("%5s %-5s %8s %s\n", "PID", "TTY", "TIME", "CMD"))
end

for _, p in ipairs(procs) do
	local tty = fmt_tty(p.tty_nr)
	local show = all or (p.uid == myuid and tty ~= "?")
	if show then
		if full then
			local pw = pwd.getpwuid(p.uid)
			local uname = pw and pw.pw_name or tostring(p.uid)
			unistd.write(1, string.format("%-8s %5d %5d %-5s %s\n",
				uname, p.pid, p.ppid, tty, p.comm))
		else
			unistd.write(1, string.format("%5d %-5s %8s %s\n",
				p.pid, tty, "00:00:00", p.comm))
		end
	end
end
