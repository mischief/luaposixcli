#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")

local fmt = nil
for _, a in ipairs(arg) do
	if a:sub(1, 1) == "+" then
		fmt = a:sub(2)
	end
end

if not fmt then
	fmt = "%a %b %e %H:%M:%S %Z %Y"
end

unistd.write(1, os.date(fmt) .. "\n")
