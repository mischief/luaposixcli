#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local stdlib = require("posix.stdlib")
local unistd = require("posix.unistd")

local dir_mode = false
local template = "/tmp/tmp.XXXXXX"
for _, a in ipairs(arg) do
	if a == "-d" then
		dir_mode = true
	else
		template = a
	end
end

if dir_mode then
	local path = stdlib.mkdtemp(template)
	if not path then
		unistd.write(2, "mktemp: failed\n")
		os.exit(1)
	end
	unistd.write(1, path .. "\n")
else
	local fd, path = stdlib.mkstemp(template)
	if not fd then
		unistd.write(2, "mktemp: failed\n")
		os.exit(1)
	end
	unistd.close(fd)
	unistd.write(1, path .. "\n")
end
