#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local prefix = ((arg[0] or "mv"):match("(.+/)") or "./") .. "../"
package.path = prefix .. "?.lua;" .. prefix .. "share/lua/5.4/?.lua;" .. package.path

local unistd = require("posix.unistd")
local stdio = require("posix.stdio")
local stat = require("posix.sys.stat")
local util = require("luaposixcli.util")

local force, interactive = false, false
local operands = {}
local status = 0

local function usage()
	unistd.write(2, "usage: mv [-fi] source... target\n")
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
			if c == "f" then force = true; interactive = false
			elseif c == "i" then interactive = true; force = false
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

-- rename cannot cross a filesystem, and that is the one failure worth
-- recovering from: copy the bytes, then drop the original.
local function copy_over(source, dest)
	local data, err = util.slurp(source)
	if not data then return nil, err end
	local f, werr = io.open(dest, "wb")
	if not f then return nil, werr end
	f:write(data)
	f:close()
	local st = stat.stat(source)
	if st then stat.chmod(dest, st.st_mode & tonumber("7777", 8)) end
	unistd.unlink(source)
	return true
end

for _, source in ipairs(sources) do
	local dest = into_dir and (target .. "/" .. util.basename(source)) or target
	local go = true
	if stat.lstat(dest) and interactive then
		unistd.write(2, "mv: overwrite " .. dest .. "? ")
		local answer = io.read("l")
		go = answer ~= nil and answer:lower():sub(1, 1) == "y"
	end
	if go then
		if force then unistd.unlink(dest) end
		local ok, err = stdio.rename(source, dest)
		if not ok then
			local copied, cerr = copy_over(source, dest)
			if not copied then
				util.warn(cerr or err or (source .. ": cannot move"))
				status = 1
			end
		end
	end
end

os.exit(status)
