#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local utsname = require("posix.sys.utsname")

local u = utsname.uname()
local want = {}
local order = { "s", "n", "r", "v", "m" }
local field = {
	s = u.sysname, n = u.nodename, r = u.release,
	v = u.version, m = u.machine,
}

for opt, _, _ in unistd.getopt(arg, "amnrsv") do
	if opt == "a" then
		for _, c in ipairs(order) do want[c] = true end
	elseif field[opt] then
		want[opt] = true
	else
		unistd.write(2, "usage: uname [-amnrsv]\n")
		os.exit(2)
	end
end

local out = {}
for _, c in ipairs(order) do
	if want[c] then out[#out + 1] = field[c] end
end
if #out == 0 then out[1] = u.sysname end

unistd.write(1, table.concat(out, " ") .. "\n")
