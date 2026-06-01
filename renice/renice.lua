#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local notposix = require("luaposixcli.sys")

local incr = nil
local which = notposix.PRIO_PROCESS
local optind = 0

for opt, optarg, oi in unistd.getopt(arg, "n:pgu") do
	if opt == "n" then
		incr = tonumber(optarg)
	elseif opt == "p" then
		which = notposix.PRIO_PROCESS
	elseif opt == "g" then
		which = notposix.PRIO_PGRP
	elseif opt == "u" then
		which = notposix.PRIO_USER
	end
	optind = oi
end

local ids = {}
for i = optind, #arg do
	ids[#ids + 1] = tonumber(arg[i])
end

if not incr or #ids == 0 then
	unistd.write(2, "renice: usage: renice -n increment [-p|-g|-u] id...\n")
	os.exit(1)
end

local status = 0
for _, id in ipairs(ids) do
	local cur = notposix.getpriority(which, id)
	if not cur then
		unistd.write(2, "renice: " .. id .. ": getpriority failed\n")
		status = 1
	else
		local ok, err = notposix.setpriority(which, id, cur + incr)
		if not ok then
			unistd.write(2, "renice: " .. id .. ": " .. err .. "\n")
			status = 1
		end
	end
end
os.exit(status)
