#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
-- mesg - whether other people may write to this terminal
local prefix = ((arg[0] or "mesg"):match("(.+/)") or "./") .. "../"
package.path = prefix .. "?.lua;" .. prefix .. "share/lua/5.4/?.lua;" .. package.path

local unistd = require("posix.unistd")
local stat = require("posix.sys.stat")
local util = require("luaposixcli.util")

local function usage()
	util.die("usage: mesg [y|n]", 2)
end

local optind = 1
for opt in unistd.getopt(arg, "") do
	if opt == "?" then usage() end
	optind = optind + 1
end
local operands = util.operands(arg, optind)
if #operands > 1 then usage() end

-- The terminal this is about is the one on standard input, which is
-- where write would send its lines
local name = unistd.ttyname(0)
if not name then util.die("not a terminal", 2) end

local st = stat.stat(name)
if not st then util.die(name .. ": cannot read") end

local bits = st.st_mode & tonumber("7777", 8)
local open_now = (bits & stat.S_IWGRP) ~= 0

if #operands == 0 then
	unistd.write(1, (open_now and "is y" or "is n") .. "\n")
	os.exit(open_now and 0 or 1)
end

local want = operands[1]
if want == "y" then
	bits = bits | stat.S_IWGRP
elseif want == "n" then
	bits = bits & ~stat.S_IWGRP
else
	usage()
end

local ok, err = stat.chmod(name, bits)
if not ok then util.die(name .. ": " .. tostring(err)) end
os.exit(want == "y" and 0 or 1)
