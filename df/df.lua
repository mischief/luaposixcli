#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local statvfs = require("posix.sys.statvfs")

local paths = #arg > 0 and arg or { "/" }

unistd.write(
	1,
	string.format("%-20s %10s %10s %10s %5s %s\n", "Filesystem", "1K-blocks", "Used", "Available", "Use%", "Mounted on")
)

for _, path in ipairs(paths) do
	local s = statvfs.statvfs(path)
	if not s then
		unistd.write(2, "df: " .. path .. ": No such file or directory\n")
	else
		local bsize = s.f_frsize
		local total = s.f_blocks * bsize // 1024
		local free = s.f_bfree * bsize // 1024
		local avail = s.f_bavail * bsize // 1024
		local used = total - free
		local pct = total > 0 and math.floor(used * 100 / (used + avail) + 0.5) or 0
		unistd.write(1, string.format("%-20s %10d %10d %10d %4d%% %s\n", "-", total, used, avail, pct, path))
	end
end
