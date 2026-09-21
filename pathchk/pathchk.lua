#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
-- pathchk - whether a path name is usable
local prefix = ((arg[0] or "pathchk"):match("(.+/)") or "./") .. "../"
package.path = prefix .. "?.lua;" .. prefix .. "share/lua/5.4/?.lua;" .. package.path

local unistd = require("posix.unistd")
local util = require("luaposixcli.util")

-- POSIX's own floors, which -p checks against instead of this system's
local POSIX_PATH_MAX = 256
local POSIX_NAME_MAX = 14
local PORTABLE = "^[%w._%-]*$"

local most_portable, paths = false, {}
local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "--" then
		for j = i + 1, #arg do paths[#paths + 1] = arg[j] end
		break
	elseif a:sub(1, 1) == "-" and #a > 1 then
		for c in a:sub(2):gmatch(".") do
			if c == "p" or c == "P" then most_portable = true
			else util.die("usage: pathchk [-p] [-P] pathname...", 2) end
		end
	else
		paths[#paths + 1] = a
	end
	i = i + 1
end

if #paths == 0 then util.die("usage: pathchk [-p] [-P] pathname...", 2) end

local path_max = most_portable and POSIX_PATH_MAX or 4096
local name_max = most_portable and POSIX_NAME_MAX or 255

local status = 0
local function bad(path, why)
	unistd.write(2, "pathchk: " .. path .. ": " .. why .. "\n")
	status = 1
end

for _, path in ipairs(paths) do
	if path == "" then
		bad(path, "empty path name")
	elseif #path > path_max then
		bad(path, "path name is longer than " .. path_max)
	else
		local ok = true
		for component in path:gmatch("[^/]+") do
			if #component > name_max then
				bad(path, "component is longer than " .. name_max .. ": " .. component)
				ok = false
				break
			end
			if most_portable and not component:match(PORTABLE) then
				bad(path, "component is not portable: " .. component)
				ok = false
				break
			end
		end
		-- -P also refuses a component that starts with a dash, which a
		-- utility would read as an option
		if ok and most_portable and path:match("^%-") then
			bad(path, "path name begins with a dash")
		end
	end
end
os.exit(status)
