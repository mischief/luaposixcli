#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local stat = require("posix.sys.stat")

local force = false
local files = {}
for _, a in ipairs(arg) do
	if a == "-f" then
		force = true
	else
		files[#files + 1] = a
	end
end

local status = 0
for _, f in ipairs(files) do
	local ok, err = os.remove(f)
	if not ok and not force then
		unistd.write(2, "rm: " .. f .. ": " .. (err or "No such file or directory") .. "\n")
		status = 1
	end
end
os.exit(status)
