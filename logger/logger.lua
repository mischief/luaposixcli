#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local syslog = require("posix.syslog")

local tag = "logger"
local priority = syslog.LOG_NOTICE
local facility = syslog.LOG_USER

local priorities = {
	emerg = syslog.LOG_EMERG,
	alert = syslog.LOG_ALERT,
	crit = syslog.LOG_CRIT,
	err = syslog.LOG_ERR,
	warning = syslog.LOG_WARNING,
	notice = syslog.LOG_NOTICE,
	info = syslog.LOG_INFO,
	debug = syslog.LOG_DEBUG,
}

local optind = 1
for opt, optarg, oi in unistd.getopt(arg, "t:p:") do
	if opt == "t" then tag = optarg
	elseif opt == "p" then
		local p = optarg:match("%.(.+)") or optarg
		if priorities[p] then priority = priorities[p] end
	elseif opt == "?" then
		unistd.write(2, "usage: logger [-t tag] [-p facility.priority] [message]\n")
		os.exit(1)
	end
	optind = oi
end

-- Remaining args are the message
local msg_parts = {}
for i = optind, #arg do
	msg_parts[#msg_parts + 1] = arg[i]
end
local message = table.concat(msg_parts, " ")

-- Read from stdin if no message
if message == "" then
	local buf = {}
	while true do
		local data = unistd.read(0, 4096)
		if not data or data == "" then break end
		buf[#buf + 1] = data
	end
	message = table.concat(buf):gsub("\n+$", "")
end

syslog.openlog(tag, syslog.LOG_PID, facility)
syslog.syslog(priority, message)
syslog.closelog()
