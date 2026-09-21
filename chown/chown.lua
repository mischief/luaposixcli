#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local pwd = require("posix.pwd")
local grp = require("posix.grp")
local stat = require("posix.sys.stat")
local dirent = require("posix.dirent")

local recursive, no_follow = false, false
local optind = 1

local function usage()
	unistd.write(2, "usage: chown [-hR] owner[:group] file...\n")
	os.exit(2)
end

for opt, _, oi in unistd.getopt(arg, "hR") do
	if opt == "R" then recursive = true
	elseif opt == "h" then no_follow = true
	else usage() end
	optind = oi
end
if arg[optind] == "--" then optind = optind + 1 end

local spec = arg[optind]
if not spec or optind + 1 > #arg then usage() end

local uid, gid = -1, -1
local owner, group = spec:match("^([^:]*):?(.*)$")
if owner and owner ~= "" then
	local pw = pwd.getpwnam(owner)
	uid = pw and pw.pw_uid or tonumber(owner)
	if not uid then
		unistd.write(2, "chown: invalid user: " .. owner .. "\n")
		os.exit(1)
	end
end
if group and group ~= "" then
	local gr = grp.getgrnam(group)
	gid = gr and gr.gr_gid or tonumber(group)
	if not gid then
		unistd.write(2, "chown: invalid group: " .. group .. "\n")
		os.exit(1)
	end
end

local status = 0

local function apply(path)
	local st = stat.lstat(path)
	if not st then
		unistd.write(2, "chown: " .. path .. ": No such file or directory\n")
		status = 1
		return
	end
	-- -h is about the link rather than what it points at, and luaposix
	-- has no lchown, so a link is left alone rather than followed
	if stat.S_ISLNK(st.st_mode) ~= 0 and no_follow then return end

	local ok, err = unistd.chown(path, uid, gid)
	if ok ~= 0 then
		unistd.write(2, "chown: " .. (err or path .. ": failed") .. "\n")
		status = 1
	end
	if recursive and stat.S_ISDIR(st.st_mode) ~= 0 then
		for _, name in ipairs(dirent.dir(path) or {}) do
			if name ~= "." and name ~= ".." then
				apply(path .. "/" .. name)
			end
		end
	end
end

for i = optind + 1, #arg do apply(arg[i]) end
os.exit(status)
