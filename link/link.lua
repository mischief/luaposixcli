#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")

if #arg ~= 2 then
	unistd.write(2, "link: missing operand\n")
	os.exit(1)
end

local ok, err = unistd.link(arg[1], arg[2])
if ok ~= 0 then
	unistd.write(2, "link: " .. (err or "failed") .. "\n")
	os.exit(1)
end
