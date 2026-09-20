-- SPDX-License-Identifier: ISC
-- ps/list.lua - the process table and the columns ps and top both show
local pwd = require("posix.pwd")
local ps_sys = require("ps.sys")

local M = {}

-- Controlling terminal, as a name
function M.tty(tty_nr)
	if tty_nr == 0 or tty_nr == -1 then return "?" end
	local major = (tty_nr >> 8) & 0xff
	local minor = tty_nr & 0xff
	if major == 136 then return "pts/" .. minor end
	return tostring(tty_nr)
end

-- Every process the kernel will show us, by pid
function M.procs()
	local procs = ps_sys.getprocs()
	if not procs then return nil, "cannot get process list" end
	table.sort(procs, function(a, b) return a.pid < b.pid end)
	return procs
end

function M.header(full)
	if full then
		return string.format("%-8s %5s %5s %-5s %s", "UID", "PID", "PPID", "TTY", "CMD")
	end
	return string.format("%5s %-5s %8s %s", "PID", "TTY", "TIME", "CMD")
end

function M.line(p, full)
	local tty = M.tty(p.tty_nr)
	if full then
		local pw = pwd.getpwuid(p.uid)
		local uname = pw and pw.pw_name or tostring(p.uid)
		return string.format("%-8s %5d %5d %-5s %s", uname, p.pid, p.ppid, tty, p.comm)
	end
	return string.format("%5d %-5s %8s %s", p.pid, tty, "00:00:00", p.comm)
end

return M
