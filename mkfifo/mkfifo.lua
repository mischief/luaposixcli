#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local stat = require("posix.sys.stat")

if #arg == 0 then
	unistd.write(2, "mkfifo: missing operand\n")
	os.exit(1)
end

local status = 0
for _, path in ipairs(arg) do
	local ok, err = stat.mkfifo(path, 438) -- 0666
	if not ok then
		unistd.write(2, "mkfifo: " .. path .. ": " .. (err or "failed") .. "\n")
		status = 1
	end
end
os.exit(status)
