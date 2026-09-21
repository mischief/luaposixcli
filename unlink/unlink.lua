#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")

if #arg ~= 1 or arg[1]:sub(1, 1) == "-" then
	unistd.write(2, "usage: unlink file\n")
	os.exit(2)
end

local ok, err = unistd.unlink(arg[1])
if ok ~= 0 then
	unistd.write(2, "unlink: " .. (err or arg[1] .. ": failed") .. "\n")
	os.exit(1)
end
