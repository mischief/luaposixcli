#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local statvfs = require("posix.sys.statvfs")

local human = false
local optind = 1
for opt, optarg, oi in unistd.getopt(arg, "h") do
	if opt == "h" then human = true end
	optind = oi
end

local paths = {}
for i = optind, #arg do paths[#paths + 1] = arg[i] end

-- Read mount table from /proc/mounts
local function read_mounts()
	local mounts = {}
	local f = io.open("/proc/mounts", "r") or io.open("/etc/mtab", "r")
	if not f then return mounts end
	for line in f:lines() do
		local dev, mp, fstype = line:match("^(%S+)%s+(%S+)%s+(%S+)")
		if dev and mp then
			mounts[#mounts + 1] = { dev = dev, mp = mp, fstype = fstype }
		end
	end
	f:close()
	return mounts
end

-- Find the mount entry for a given path
local function find_mount(path, mounts)
	local best, best_len = nil, 0
	for _, m in ipairs(mounts) do
		if path:sub(1, #m.mp) == m.mp and #m.mp > best_len then
			best = m; best_len = #m.mp
		end
	end
	return best
end

local function fmt_size(kb)
	if not human then return string.format("%10d", kb) end
	if kb >= 1048576 then return string.format("%9.1fG", kb / 1048576)
	elseif kb >= 1024 then return string.format("%9.1fM", kb / 1024)
	else return string.format("%9.1fK", kb) end
end

local mounts = read_mounts()
local user_paths = #paths > 0

-- If no paths given, show all mounted filesystems
if #paths == 0 then
	for _, m in ipairs(mounts) do
		-- Skip kernel internal mounts that have no meaningful size
		if m.fstype ~= "sysfs" and m.fstype ~= "proc" and m.fstype ~= "cgroup"
			and m.fstype ~= "cgroup2" and m.fstype ~= "pstore"
			and m.fstype ~= "debugfs" and m.fstype ~= "tracefs"
			and m.fstype ~= "securityfs" and m.fstype ~= "configfs"
			and m.fstype ~= "fusectl" and m.fstype ~= "mqueue"
			and m.fstype ~= "hugetlbfs" and m.fstype ~= "binfmt_misc"
			and m.fstype ~= "autofs" and m.fstype ~= "nsfs" then
			paths[#paths + 1] = m.mp
		end
	end
	if #paths == 0 then paths[1] = "/" end
end

local size_hdr = human and "      Size" or " 1K-blocks"

-- Collect all rows first to determine column width
local rows = {}
local seen = {}
for _, path in ipairs(paths) do
	local s = statvfs.statvfs(path)
	if not s then
		if user_paths then
			unistd.write(2, "df: " .. path .. ": No such file or directory\n")
		end
	else
		local m = find_mount(path, mounts)
		local dev = m and m.dev or "-"
		local mp = m and m.mp or path
		if not seen[dev] then
			seen[dev] = true
			local bsize = s.f_frsize
			local total = s.f_blocks * bsize // 1024
			local free = s.f_bfree * bsize // 1024
			local avail = s.f_bavail * bsize // 1024
			local used = total - free
			local pct = total > 0 and math.floor(used * 100 / (used + avail) + 0.5) or 0
			rows[#rows + 1] = { dev = dev, total = total, used = used, avail = avail, pct = pct, mp = mp }
		end
	end
end

-- Determine filesystem column width
local fs_width = #"Filesystem"
for _, r in ipairs(rows) do
	if #r.dev > fs_width then fs_width = #r.dev end
end

local hdr_fmt = "%-" .. fs_width .. "s %10s %10s %10s %5s %s\n"
local row_fmt = "%-" .. fs_width .. "s %s %s %s %4d%% %s\n"
unistd.write(1, string.format(hdr_fmt, "Filesystem", size_hdr, "Used", "Available", "Use%", "Mounted on"))
for _, r in ipairs(rows) do
	unistd.write(1, string.format(row_fmt, r.dev, fmt_size(r.total), fmt_size(r.used), fmt_size(r.avail), r.pct, r.mp))
end
