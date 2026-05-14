#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")

local name = unistd.getlogin()
if not name then
	unistd.write(2, "logname: no login name\n")
	os.exit(1)
end
unistd.write(1, name .. "\n")
