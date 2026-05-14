#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local out = (#arg > 0 and table.concat(arg, " ") or "y") .. "\n"
while true do
	unistd.write(1, out)
end
