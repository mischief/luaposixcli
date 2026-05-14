#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local wait = require("posix.sys.wait")
local sys_time = require("posix.sys.time")

if #arg == 0 then
	unistd.write(2, "time: missing command\n")
	os.exit(1)
end

local function now()
	local tv = sys_time.gettimeofday()
	return tv.tv_sec + tv.tv_usec / 1000000
end

local t0 = now()
local pid = unistd.fork()
if pid == 0 then
	unistd.execp(arg[1], arg)
	os.exit(127)
end

local _, reason, status = wait.wait(pid)
local elapsed = now() - t0

local m = math.floor(elapsed / 60)
local s = elapsed - m * 60
unistd.write(2, string.format("\nreal\t%dm%.3fs\n", m, s))

if reason == "exited" then
	os.exit(status)
elseif reason == "killed" then
	os.exit(128 + status)
else
	os.exit(1)
end
