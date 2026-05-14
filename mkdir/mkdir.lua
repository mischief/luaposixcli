#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local stat = require("posix.sys.stat")
local unistd = require("posix.unistd")

local status = 0
for _, d in ipairs(arg) do
	local ok, err = stat.mkdir(d, 493) -- 0755
	if not ok then
		unistd.write(2, "mkdir: " .. d .. ": " .. (err or "failed") .. "\n")
		status = 1
	end
end
os.exit(status)
