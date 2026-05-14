#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")

local incr = 10
local cmd_start = 1
for i, a in ipairs(arg) do
	if a == "-n" then
		incr = tonumber(arg[i + 1]) or 10
		cmd_start = i + 2
		break
	elseif a:match("^%-n%d") then
		incr = tonumber(a:sub(3))
		cmd_start = i + 1
		break
	elseif not a:match("^%-") then
		cmd_start = i
		break
	end
end

unistd.nice(incr)

if cmd_start <= #arg then
	local cmd_args = {}
	for i = cmd_start, #arg do
		cmd_args[#cmd_args + 1] = arg[i]
	end
	unistd.execp(arg[cmd_start], cmd_args)
	os.exit(127)
end
