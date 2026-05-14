#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local syslog = require("posix.syslog")

local tag = nil
local priority = syslog.LOG_NOTICE
local facility = syslog.LOG_USER
local msg_parts = {}

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

local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "-t" then
		i = i + 1
		tag = arg[i]
	elseif a == "-p" then
		i = i + 1
		local spec = arg[i] or ""
		local p = spec:match("%.(.+)") or spec
		if priorities[p] then
			priority = priorities[p]
		end
	else
		msg_parts[#msg_parts + 1] = a
	end
	i = i + 1
end

local message = table.concat(msg_parts, " ")

-- read from stdin if no message
if message == "" then
	local buf = {}
	while true do
		local data = unistd.read(0, 4096)
		if not data or data == "" then
			break
		end
		buf[#buf + 1] = data
	end
	message = table.concat(buf):gsub("\n+$", "")
end

syslog.openlog(tag or "logger", syslog.LOG_PID, facility)
syslog.syslog(priority, message)
syslog.closelog()
