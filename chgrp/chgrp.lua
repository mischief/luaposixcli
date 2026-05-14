#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local grp = require("posix.grp")

if #arg < 2 then
	unistd.write(2, "chgrp: missing operand\n")
	os.exit(1)
end

local group = arg[1]
local gr = grp.getgrnam(group)
local gid = gr and gr.gr_gid or tonumber(group)
if not gid then
	unistd.write(2, "chgrp: invalid group: " .. group .. "\n")
	os.exit(1)
end

local status = 0
for i = 2, #arg do
	local ok, err = unistd.chown(arg[i], -1, gid)
	if ok ~= 0 then
		unistd.write(2, "chgrp: " .. arg[i] .. ": " .. (err or "failed") .. "\n")
		status = 1
	end
end
os.exit(status)
