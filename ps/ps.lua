#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local dirent = require("posix.dirent")
local fcntl = require("posix.fcntl")
local pwd = require("posix.pwd")

local all = false
local full = false

for _, a in ipairs(arg) do
	if a == "-A" or a == "-e" then
		all = true
	elseif a == "-f" then
		full = true
	elseif a == "-Af" or a == "-eA" or a == "-ef" then
		all = true
		full = true
	else
		for i = 2, #a do
			local c = a:sub(i, i)
			if c == "A" or c == "e" then
				all = true
			elseif c == "f" then
				full = true
			end
		end
	end
end

local myuid = unistd.getuid()

local function read_file(path)
	local fd = fcntl.open(path, fcntl.O_RDONLY)
	if not fd then
		return nil
	end
	local data = unistd.read(fd, 4096)
	unistd.close(fd)
	return data
end

local function get_proc(pid)
	local stat = read_file("/proc/" .. pid .. "/stat")
	if not stat then
		return nil
	end

	-- parse: pid (comm) state ppid pgrp session tty_nr tpgid ...
	local p, comm, state, ppid = stat:match("^(%d+) %((.-)%) (%S) (%d+)")
	if not p then
		return nil
	end

	-- get uid from status
	local status = read_file("/proc/" .. pid .. "/status")
	local uid = 0
	if status then
		uid = tonumber(status:match("Uid:%s+(%d+)")) or 0
	end

	-- get cmdline
	local cmdline = read_file("/proc/" .. pid .. "/cmdline")
	local cmd = comm
	if cmdline and #cmdline > 0 then
		cmd = cmdline:gsub("%z", " "):gsub("%s+$", "")
	end

	-- get tty
	local tty_nr = tonumber(stat:match("^%d+ %(.-%)" .. " %S %d+ %d+ %d+ (%d+)")) or 0
	local tty = "?"
	if tty_nr ~= 0 then
		local major = (tty_nr >> 8) & 0xff
		local minor = tty_nr & 0xff
		if major == 136 then
			tty = "pts/" .. minor
		else
			tty = tostring(tty_nr)
		end
	end

	-- stime (start time) - use field 22 (starttime in ticks)
	local stime = "00:00"

	return {
		pid = tonumber(p),
		ppid = tonumber(ppid),
		uid = uid,
		tty = tty,
		cmd = cmd,
		comm = comm,
		stime = stime,
	}
end

-- header
if full then
	unistd.write(1, string.format("%-8s %5s %5s %5s %-6s %-5s %s\n", "UID", "PID", "PPID", "C", "STIME", "TTY", "CMD"))
else
	unistd.write(1, string.format("%5s %-6s %8s %s\n", "PID", "TTY", "TIME", "CMD"))
end

local entries = dirent.dir("/proc")
table.sort(entries, function(a, b)
	return (tonumber(a) or 0) < (tonumber(b) or 0)
end)

for _, e in ipairs(entries) do
	if e:match("^%d+$") then
		local p = get_proc(e)
		if p then
			local show = all or (p.uid == myuid and p.tty ~= "?")
			if show then
				if full then
					local pw = pwd.getpwuid(p.uid)
					local uname = pw and pw.pw_name or tostring(p.uid)
					unistd.write(
						1,
						string.format("%-8s %5d %5d %5d %-6s %-5s %s\n", uname, p.pid, p.ppid, 0, p.stime, p.tty, p.cmd)
					)
				else
					unistd.write(1, string.format("%5d %-6s %8s %s\n", p.pid, p.tty, "00:00:00", p.comm))
				end
			end
		end
	end
end
