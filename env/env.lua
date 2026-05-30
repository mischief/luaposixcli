#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
-- env - set environment and execute command, or print environment
local unistd = require("posix.unistd")
local stdlib = require("posix.stdlib")

local clear = false
local i = 1

-- Parse options
while i <= #arg do
	if arg[i] == "-i" or arg[i] == "-" then
		clear = true
	elseif arg[i] == "--" then
		i = i + 1
		break
	elseif arg[i]:sub(1, 1) == "-" then
		unistd.write(2, "env: invalid option -- '" .. arg[i]:sub(2) .. "'\n")
		os.exit(125)
	else
		break
	end
	i = i + 1
end

-- Process NAME=VALUE pairs
while i <= #arg and arg[i]:find("=") do
	local name, val = arg[i]:match("^([^=]+)=(.*)")
	if name then stdlib.setenv(name, val, true) end
	i = i + 1
end

-- No command: print environment
if i > #arg then
	for k, v in pairs(stdlib.getenv()) do
		if type(k) == "string" then
			unistd.write(1, k .. "=" .. v .. "\n")
		end
	end
	os.exit(0)
end

-- Execute command
local cmd = arg[i]
local cmd_args = {}
for j = i + 1, #arg do cmd_args[#cmd_args + 1] = arg[j] end
unistd.execp(cmd, cmd_args)
unistd.write(2, "env: '" .. cmd .. "': No such file or directory\n")
os.exit(127)
