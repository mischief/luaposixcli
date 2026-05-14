#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")

if #arg == 0 then
	unistd.write(2, "unlink: missing operand\n")
	os.exit(1)
end

local ok, err = unistd.unlink(arg[1])
if ok ~= 0 then
	unistd.write(2, "unlink: " .. (err or "failed") .. "\n")
	os.exit(1)
end
