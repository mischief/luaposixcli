#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local pwd = require("posix.pwd")
local grp = require("posix.grp")

if #arg < 2 then
	unistd.write(2, "chown: missing operand\n")
	os.exit(1)
end

local spec = arg[1]
local uid, gid = -1, -1

-- parse owner[:group]
local owner, group = spec:match("^([^:]*):?(.*)$")
if owner and owner ~= "" then
	local pw = pwd.getpwnam(owner)
	if pw then
		uid = pw.pw_uid
	else
		uid = tonumber(owner) or -1
	end
end
if group and group ~= "" then
	local gr = grp.getgrnam(group)
	if gr then
		gid = gr.gr_gid
	else
		gid = tonumber(group) or -1
	end
end

local status = 0
for i = 2, #arg do
	local ok, err = unistd.chown(arg[i], uid, gid)
	if ok ~= 0 then
		unistd.write(2, "chown: " .. arg[i] .. ": " .. (err or "failed") .. "\n")
		status = 1
	end
end
os.exit(status)
