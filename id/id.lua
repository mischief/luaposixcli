#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local grp = require("posix.grp")
local pwd = require("posix.pwd")

local uid = unistd.getuid()
local gid = unistd.getgid()
local pw = pwd.getpwuid(uid)
local gr = grp.getgrgid(gid)
local uname = pw and pw.pw_name or tostring(uid)
local gname = gr and gr.gr_name or tostring(gid)

local groups = unistd.getgroups() or {}
local gstr = {}
for _, g in ipairs(groups) do
	local gi = grp.getgrgid(g)
	gstr[#gstr + 1] = g .. "(" .. (gi and gi.gr_name or tostring(g)) .. ")"
end

unistd.write(1, string.format("uid=%d(%s) gid=%d(%s) groups=%s\n", uid, uname, gid, gname, table.concat(gstr, ",")))
