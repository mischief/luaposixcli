#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local prefix = ((arg[0] or "chmod"):match("(.+/)") or "./") .. "../"
package.path = prefix .. "?.lua;" .. prefix .. "share/lua/5.4/?.lua;" .. package.path

local stat = require("posix.sys.stat")
local unistd = require("posix.unistd")
local dirent = require("posix.dirent")
local mode_of = require("luaposixcli.mode")

local ALLBITS = tonumber("7777", 8)

local function die(msg)
	unistd.write(2, "chmod: " .. msg .. "\n")
	os.exit(1)
end

local recursive = false
local optind = 1
for opt, _, oi in unistd.getopt(arg, "R") do
	if opt == "R" then recursive = true
	else
		unistd.write(2, "usage: chmod [-R] mode file...\n")
		os.exit(2)
	end
	optind = oi
end
if arg[optind] == "--" then optind = optind + 1 end

local mode_str = arg[optind]
local files = {}
for i = optind + 1, #arg do files[#files + 1] = arg[i] end

if not mode_str or #files == 0 then
	die("missing operand")
end

if not mode_str:match("^[0-7]+$") and not mode_str:match("^[ugoa]*[-+=]") then
	die("invalid mode: " .. mode_str)
end

local status = 0

local function chmod_one(path)
	local st = stat.stat(path)
	if not st then
		unistd.write(2, "chmod: " .. path .. ": cannot stat\n")
		status = 1
		return
	end
	local isdir = stat.S_ISDIR(st.st_mode) ~= 0
	local mode, err = mode_of.parse(mode_str, st.st_mode & ALLBITS, isdir)
	if not mode then die(err) end
	local ok, err = stat.chmod(path, mode)
	if not ok then
		unistd.write(2, "chmod: " .. path .. ": " .. (err or "failed") .. "\n")
		status = 1
	end
	if recursive and isdir then
		for name in dirent.files(path) do
			if name ~= "." and name ~= ".." then
				chmod_one(path .. "/" .. name)
			end
		end
	end
end

for _, path in ipairs(files) do chmod_one(path) end
os.exit(status)
