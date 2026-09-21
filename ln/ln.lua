#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local prefix = ((arg[0] or "ln"):match("(.+/)") or "./") .. "../"
package.path = prefix .. "?.lua;" .. prefix .. "share/lua/5.4/?.lua;" .. package.path

local unistd = require("posix.unistd")
local stat = require("posix.sys.stat")
local util = require("luaposixcli.util")

local symbolic, force = false, false
local operands = {}
local status = 0

local function usage()
	unistd.write(2, "usage: ln [-fs] source... target\n")
	os.exit(2)
end

local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "--" then
		for j = i + 1, #arg do operands[#operands + 1] = arg[j] end
		break
	elseif a:sub(1, 1) == "-" and #a > 1 then
		for c in a:sub(2):gmatch(".") do
			if c == "s" then symbolic = true
			elseif c == "f" then force = true
			else usage() end
		end
	else
		operands[#operands + 1] = a
	end
	i = i + 1
end

if #operands < 2 then usage() end

local target = operands[#operands]
local sources = {}
for n = 1, #operands - 1 do sources[#sources + 1] = operands[n] end

local target_stat = stat.stat(target)
local into_dir = target_stat and stat.S_ISDIR(target_stat.st_mode) ~= 0
if #sources > 1 and not into_dir then
	util.die(target .. ": not a directory")
end

for _, source in ipairs(sources) do
	local dest = into_dir and (target .. "/" .. util.basename(source)) or target
	if force then unistd.unlink(dest) end
	local ok, err = unistd.link(source, dest, symbolic)
	if ok ~= 0 then
		util.warn(err or (dest .. ": cannot link"))
		status = 1
	end
end

os.exit(status)
