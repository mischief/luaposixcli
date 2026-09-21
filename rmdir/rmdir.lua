#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local prefix = ((arg[0] or "rmdir"):match("(.+/)") or "./") .. "../"
package.path = prefix .. "?.lua;" .. prefix .. "share/lua/5.4/?.lua;" .. package.path

local unistd = require("posix.unistd")
local util = require("luaposixcli.util")

local parents = false
local dirs = {}
local status = 0

local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "--" then
		for j = i + 1, #arg do dirs[#dirs + 1] = arg[j] end
		break
	elseif a:sub(1, 1) == "-" and #a > 1 then
		for c in a:sub(2):gmatch(".") do
			if c == "p" then parents = true
			else
				unistd.write(2, "usage: rmdir [-p] directory...\n")
				os.exit(2)
			end
		end
	else
		dirs[#dirs + 1] = a
	end
	i = i + 1
end

if #dirs == 0 then
	unistd.write(2, "usage: rmdir [-p] directory...\n")
	os.exit(2)
end

for _, dir in ipairs(dirs) do
	local path = dir:gsub("/+$", "")
	local ok, err = unistd.rmdir(path)
	if ok ~= 0 then
		util.warn(err or (path .. ": failed"))
		status = 1
	elseif parents then
		-- and then each parent, stopping at the first that will not go
		path = path:match("^(.*)/[^/]+$")
		while path and path ~= "" do
			if unistd.rmdir(path) ~= 0 then break end
			path = path:match("^(.*)/[^/]+$")
		end
	end
end

os.exit(status)
