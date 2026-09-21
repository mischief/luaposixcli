#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local grp = require("posix.grp")
local stat = require("posix.sys.stat")
local dirent = require("posix.dirent")

local recursive, no_follow = false, false
local optind = 1

local function usage()
	unistd.write(2, "usage: chgrp [-hR] group file...\n")
	os.exit(2)
end

for opt, _, oi in unistd.getopt(arg, "hR") do
	if opt == "R" then recursive = true
	elseif opt == "h" then no_follow = true
	else usage() end
	optind = oi
end

local group = arg[optind]
if not group or optind + 1 > #arg then usage() end

local gr = grp.getgrnam(group)
local gid = gr and gr.gr_gid or tonumber(group)
if not gid then
	unistd.write(2, "chgrp: invalid group: " .. group .. "\n")
	os.exit(1)
end

local status = 0

local function apply(path)
	local st = stat.lstat(path)
	if not st then
		unistd.write(2, "chgrp: " .. path .. ": No such file or directory\n")
		status = 1
		return
	end
	if stat.S_ISLNK(st.st_mode) ~= 0 and no_follow then return end

	local ok, err = unistd.chown(path, -1, gid)
	if ok ~= 0 then
		unistd.write(2, "chgrp: " .. (err or path .. ": failed") .. "\n")
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
