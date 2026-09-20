-- SPDX-License-Identifier: ISC
-- pty_pair.lua - run two programs on the ends of a pty pair and pump
-- bytes between them. Used by the zmodem test: sz and rz both insist on
-- a terminal, and a pipe is not one.
--
--   lua5.4 pty_pair.lua "cmd one" "dir one" "cmd two" "dir two"
local unistd = require("posix.unistd")
local stdlib = require("posix.stdlib")
local poll = require("posix.poll")
local wait = require("posix.sys.wait")
local fcntl = require("posix.fcntl")
local termio = require("posix.termio")

local function open_pty()
	local master = stdlib.openpt(fcntl.O_RDWR)
	assert(master, "cannot open a pty")
	stdlib.grantpt(master)
	stdlib.unlockpt(master)
	return master, stdlib.ptsname(master)
end

local function raw(fd)
	local t = termio.tcgetattr(fd)
	if not t then return end
	t.lflag = t.lflag & ~(termio.ICANON | termio.ECHO | termio.ISIG)
	t.iflag = t.iflag & ~(termio.IXON | termio.ICRNL)
	t.oflag = t.oflag & ~termio.OPOST
	t.cc[termio.VMIN] = 1
	t.cc[termio.VTIME] = 0
	termio.tcsetattr(fd, termio.TCSANOW, t)
end

local function spawn(cmd, dir, slave_name)
	local pid = unistd.fork()
	if pid == 0 then
		unistd.setpid("s")
		local fd = fcntl.open(slave_name, fcntl.O_RDWR)
		raw(fd)
		unistd.dup2(fd, 0)
		unistd.dup2(fd, 1)
		if fd > 2 then unistd.close(fd) end
		unistd.chdir(dir)
		unistd.execp("/bin/sh", { "-c", cmd })
		os.exit(127)
	end
	return pid
end

local m1, s1 = open_pty()
local m2, s2 = open_pty()

local p1 = spawn(arg[1], arg[2], s1)
local p2 = spawn(arg[3], arg[4], s2)

local left = { [p1] = true, [p2] = true }
local other = { [m1] = m2, [m2] = m1 }
local deadline = os.time() + 30

local fds = {
	[m1] = { events = { IN = true } },
	[m2] = { events = { IN = true } },
}

while next(left) and os.time() < deadline do
	local ready = poll.poll(fds, 200)
	if ready and ready > 0 then
		for fd, d in pairs(fds) do
			if d.revents and d.revents.IN then
				local data = unistd.read(fd, 4096)
				if data and data ~= "" then
					unistd.write(other[fd], data)
				end
			end
		end
	end
	for pid in pairs(left) do
		local done = wait.wait(pid, wait.WNOHANG)
		if done == pid then left[pid] = nil end
	end
end

for pid in pairs(left) do
	require("posix.signal").kill(pid, 9)
	wait.wait(pid)
end
