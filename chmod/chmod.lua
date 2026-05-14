#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local stat = require("posix.sys.stat")
local unistd = require("posix.unistd")

if #arg < 2 then
	unistd.write(2, "chmod: missing operand\n")
	os.exit(1)
end

local mode_str = arg[1]
local mode = tonumber(mode_str, 8)
if not mode then
	unistd.write(2, "chmod: invalid mode: " .. mode_str .. "\n")
	os.exit(1)
end

local status = 0
for i = 2, #arg do
	local ok, err = stat.chmod(arg[i], mode)
	if not ok then
		unistd.write(2, "chmod: " .. arg[i] .. ": " .. (err or "failed") .. "\n")
		status = 1
	end
end
os.exit(status)
