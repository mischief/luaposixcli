#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local dirent = require("posix.dirent")
local stat = require("posix.sys.stat")
local unistd = require("posix.unistd")
local pwd = require("posix.pwd")
local grp = require("posix.grp")

local show_all = false
local long = false
local one_per_line = false
local recursive = false
local paths = {}

local optind = 1
for opt, _, oi in unistd.getopt(arg, "al1R") do
	if opt == "a" then
		show_all = true
	elseif opt == "l" then
		long = true
	elseif opt == "1" then
		one_per_line = true
	elseif opt == "R" then
		recursive = true
	end
	optind = oi
end
for i = optind, #arg do
	paths[#paths + 1] = arg[i]
end

if #paths == 0 then
	paths = { "." }
end

local function mode_string(mode)
	local t = stat.S_ISDIR(mode) ~= 0 and "d"
		or stat.S_ISLNK(mode) ~= 0 and "l"
		or stat.S_ISFIFO(mode) ~= 0 and "p"
		or stat.S_ISSOCK(mode) ~= 0 and "s"
		or stat.S_ISBLK(mode) ~= 0 and "b"
		or stat.S_ISCHR(mode) ~= 0 and "c"
		or "-"
	local function bit(m, ch)
		return (mode & m) ~= 0 and ch or "-"
	end
	return t
		.. bit(0x100, "r")
		.. bit(0x080, "w")
		.. bit(0x040, "x")
		.. bit(0x020, "r")
		.. bit(0x010, "w")
		.. bit(0x008, "x")
		.. bit(0x004, "r")
		.. bit(0x002, "w")
		.. bit(0x001, "x")
end

local function format_time(mtime)
	return os.date("%b %d %H:%M", mtime)
end

local function list_dir(path, show_header)
	local entries = dirent.dir(path)
	if not entries then
		unistd.write(2, "ls: " .. path .. ": No such file or directory\n")
		return
	end
	table.sort(entries)

	if show_header then
		unistd.write(1, "\n" .. path .. ":\n")
	end

	local output = {}
	local subdirs = {}
	for _, name in ipairs(entries) do
		if show_all or name:sub(1, 1) ~= "." then
			local full = (path == ".") and name or (path .. "/" .. name)
			if long then
				local s = stat.lstat(full)
				if s then
					local pw = pwd.getpwuid(s.st_uid)
					local gr = grp.getgrgid(s.st_gid)
					output[#output + 1] = string.format(
						"%s %2d %-8s %-8s %8d %s %s",
						mode_string(s.st_mode),
						s.st_nlink,
						pw and pw.pw_name or tostring(s.st_uid),
						gr and gr.gr_name or tostring(s.st_gid),
						s.st_size,
						format_time(s.st_mtime),
						name
					)
				end
			else
				output[#output + 1] = name
			end
			if recursive then
				local s = stat.lstat(full)
				if s and stat.S_ISDIR(s.st_mode) ~= 0 then
					subdirs[#subdirs + 1] = full
				end
			end
		end
	end

	if long or one_per_line then
		unistd.write(1, table.concat(output, "\n") .. "\n")
	else
		unistd.write(1, table.concat(output, "  ") .. "\n")
	end

	for _, sub in ipairs(subdirs) do
		list_dir(sub, true)
	end
end

for _, path in ipairs(paths) do
	local s = stat.lstat(path)
	if not s then
		unistd.write(2, "ls: " .. path .. ": No such file or directory\n")
		os.exit(1)
	end

	if stat.S_ISDIR(s.st_mode) == 0 then
		if long then
			local pw = pwd.getpwuid(s.st_uid)
			local gr = grp.getgrgid(s.st_gid)
			unistd.write(
				1,
				string.format(
					"%s %2d %-8s %-8s %8d %s %s\n",
					mode_string(s.st_mode),
					s.st_nlink,
					pw and pw.pw_name or tostring(s.st_uid),
					gr and gr.gr_name or tostring(s.st_gid),
					s.st_size,
					format_time(s.st_mtime),
					path
				)
			)
		else
			unistd.write(1, path .. "\n")
		end
	else
		list_dir(path, #paths > 1 or recursive)
	end
end
