#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local stdio = require("posix.stdio")

if #arg < 2 then
	unistd.write(2, "mv: missing operand\n")
	os.exit(1)
end

local src = arg[1]
local dst = arg[2]

local ok, err = stdio.rename(src, dst)
if not ok then
	unistd.write(2, "mv: " .. (err or "failed") .. "\n")
	os.exit(1)
end
