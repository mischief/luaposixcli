#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")

-- POSIX echo has no options, but -n is what every other shell does and
-- what scripts expect.
local first = 1
local newline = "\n"
if arg[1] == "-n" then
	first = 2
	newline = ""
end

local words = {}
for i = first, #arg do words[#words + 1] = arg[i] end
unistd.write(1, table.concat(words, " ") .. newline)
