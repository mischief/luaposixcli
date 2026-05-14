#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd   = require("posix.unistd")
local notposix = require("notposix")

for _, entry in ipairs(notposix.environ()) do
	unistd.write(1, entry .. "\n")
end
