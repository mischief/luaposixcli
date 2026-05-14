#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
if not unistd.isatty(0) then
	io.stderr:write("not a tty\n")
	os.exit(1)
end
print(unistd.ttyname(0))
