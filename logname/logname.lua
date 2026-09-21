#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")

-- POSIX logname takes neither options nor operands
if #arg > 0 then
	unistd.write(2, "usage: logname\n")
	os.exit(2)
end

local name = unistd.getlogin()
if not name then
	unistd.write(2, "logname: no login name\n")
	os.exit(1)
end
unistd.write(1, name .. "\n")
