#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
-- timeout - run a command, and end it if it takes too long
local prefix = ((arg[0] or "timeout"):match("(.+/)") or "./") .. "../"
package.path = prefix .. "?.lua;" .. prefix .. "share/lua/5.4/?.lua;" .. package.path

local unistd = require("posix.unistd")
local signal = require("posix.signal")
local wait = require("posix.sys.wait")
local util = require("luaposixcli.util")

local signals = {
	HUP = signal.SIGHUP, INT = signal.SIGINT, QUIT = signal.SIGQUIT,
	KILL = signal.SIGKILL, TERM = signal.SIGTERM, USR1 = signal.SIGUSR1,
	USR2 = signal.SIGUSR2, ALRM = signal.SIGALRM, CONT = signal.SIGCONT,
}

local sig = signal.SIGTERM
local preserve_status = false
local kill_after = nil

local function usage()
	util.die("usage: timeout [-fp] [-k time] [-s signal] duration utility [argument...]", 125)
end

local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "--" then
		i = i + 1
		break
	elseif a:sub(1, 2) == "-s" or a:sub(1, 2) == "-k" then
		local which = a:sub(2, 2)
		local value = a:sub(3)
		if value == "" then
			i = i + 1
			value = arg[i] or usage()
		end
		if which == "s" then
			local name = value:upper():gsub("^SIG", "")
			sig = tonumber(value) or signals[name] or usage()
		else
			kill_after = tonumber(value) or usage()
		end
	elseif a == "-p" then
		preserve_status = true
	elseif a == "-f" then
		-- the command keeps our process group, which is the default here
	elseif a:sub(1, 1) == "-" and #a > 1 then
		usage()
	else
		break
	end
	i = i + 1
end

local duration = tonumber(arg[i])
if not duration or not arg[i + 1] then usage() end
i = i + 1

local command = {}
for j = i + 1, #arg do command[#command + 1] = arg[j] end
local utility = arg[i]

local child = unistd.fork()
if child == 0 then
	unistd.execp(utility, command)
	unistd.write(2, "timeout: " .. utility .. ": cannot execute\n")
	os.exit(127)
end

-- the alarm is how the wait is cut short: SIGALRM interrupts wait(2),
-- and the handler is what tells us which happened
local timed_out = false
signal.signal(signal.SIGALRM, function()
	timed_out = true
	signal.kill(child, sig)
	if kill_after then
		signal.signal(signal.SIGALRM, function()
			signal.kill(child, signal.SIGKILL)
		end)
		unistd.alarm(math.ceil(kill_after))
	end
end)
unistd.alarm(math.ceil(duration))

local _, reason, status
repeat
	_, reason, status = wait.wait(child)
until reason ~= nil or timed_out

unistd.alarm(0)

if timed_out and not preserve_status then
	os.exit(124)
end
if reason == "killed" then os.exit(128 + status) end
os.exit(status or 0)
