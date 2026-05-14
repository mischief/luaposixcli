#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local signal = require("posix.signal")
local unistd = require("posix.unistd")

local sig = signal.SIGTERM
local pids = {}
for _, a in ipairs(arg) do
	if a:sub(1, 1) == "-" then
		local s = a:sub(2)
		sig = tonumber(s) or signal["SIG" .. s:upper()] or signal[s:upper()]
		if not sig then
			unistd.write(2, "kill: invalid signal: " .. s .. "\n")
			os.exit(1)
		end
	else
		pids[#pids + 1] = tonumber(a)
	end
end

local status = 0
for _, pid in ipairs(pids) do
	local ok, err = signal.kill(pid, sig)
	if ok ~= 0 then
		unistd.write(2, "kill: " .. tostring(pid) .. ": " .. (err or "failed") .. "\n")
		status = 1
	end
end
os.exit(status)
