#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local prefix = ((arg[0] or "mkdir"):match("(.+/)") or "./") .. "../"
package.path = prefix .. "?.lua;" .. prefix .. "share/lua/5.4/?.lua;" .. package.path

local stat = require("posix.sys.stat")
local unistd = require("posix.unistd")
local mode_of = require("luaposixcli.mode")

local parents = false
local mode = nil
local dirs = {}

local function usage()
	unistd.write(2, "usage: mkdir [-p] [-m mode] directory...\n")
	os.exit(2)
end

local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "--" then
		for j = i + 1, #arg do dirs[#dirs + 1] = arg[j] end
		break
	elseif a:sub(1, 2) == "-m" then
		mode = a:sub(3)
		if mode == "" then
			i = i + 1
			mode = arg[i] or usage()
		end
	elseif a:sub(1, 1) == "-" and #a > 1 then
		for c in a:sub(2):gmatch(".") do
			if c == "p" then parents = true else usage() end
		end
	else
		dirs[#dirs + 1] = a
	end
	i = i + 1
end

if #dirs == 0 then usage() end

local DEFAULT = tonumber("777", 8)
local final_mode = DEFAULT
if mode then
	local m, err = mode_of.parse(mode, DEFAULT, true)
	if not m then
		unistd.write(2, "mkdir: " .. err .. "\n")
		os.exit(2)
	end
	final_mode = m
end

local status = 0

local function make(path, dir_mode)
	local ok, err = stat.mkdir(path, dir_mode)
	if not ok then return nil, err end
	-- mkdir(2) takes the umask off the mode; -m says exactly what was
	-- wanted, so put it back
	if mode and dir_mode == final_mode then stat.chmod(path, final_mode) end
	return true
end

for _, dir in ipairs(dirs) do
	if not parents then
		local ok, err = make(dir, final_mode)
		if not ok then
			unistd.write(2, "mkdir: " .. (err or dir .. ": failed") .. "\n")
			status = 1
		end
	else
		-- every level on the way, and an existing one is not an error
		local made = dir:sub(1, 1) == "/" and "/" or ""
		for part in dir:gmatch("[^/]+") do
			made = (made == "" or made == "/") and (made .. part) or (made .. "/" .. part)
			if not stat.stat(made) then
				local last = (made == dir or made == dir:gsub("/+$", ""))
				local ok, err = make(made, last and final_mode or DEFAULT)
				if not ok and not stat.stat(made) then
					unistd.write(2, "mkdir: " .. (err or made .. ": failed") .. "\n")
					status = 1
					break
				end
			end
		end
	end
end

os.exit(status)
