#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")

local status = 0
for _, d in ipairs(arg) do
	local ok, err = unistd.rmdir(d)
	if ok ~= 0 then
		unistd.write(2, "rmdir: " .. d .. ": " .. (err or "failed") .. "\n")
		status = 1
	end
end
os.exit(status)
