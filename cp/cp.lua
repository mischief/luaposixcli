#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local prefix = ((arg[0] or "cp"):match("(.+/)") or "./") .. "../"
package.path = prefix .. "?.lua;" .. prefix .. "share/lua/5.4/?.lua;" .. package.path

local unistd = require("posix.unistd")
local fcntl = require("posix.fcntl")
local stat = require("posix.sys.stat")
local dirent = require("posix.dirent")
local utime = require("posix.utime")

local force, interactive, preserve, recursive = false, false, false, false
local operands = {}
local status = 0

local function warn(msg)
	unistd.write(2, "cp: " .. msg .. "\n")
	status = 1
end

local function usage()
	unistd.write(2, "usage: cp [-fipRr] source... target\n")
	os.exit(2)
end

local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "--" then
		for j = i + 1, #arg do operands[#operands + 1] = arg[j] end
		break
	elseif a:sub(1, 1) == "-" and #a > 1 then
		for c in a:sub(2):gmatch(".") do
			if c == "f" then force = true
			elseif c == "i" then interactive = true
			elseif c == "p" then preserve = true
			elseif c == "R" or c == "r" then recursive = true
			else usage() end
		end
	else
		operands[#operands + 1] = a
	end
	i = i + 1
end

if #operands < 2 then usage() end

local target = operands[#operands]
local sources = {}
for n = 1, #operands - 1 do sources[#sources + 1] = operands[n] end

local function isdir(path)
	local st = stat.stat(path)
	return st and stat.S_ISDIR(st.st_mode) ~= 0
end

local function basename(path)
	return (path:gsub("/+$", ""):match("([^/]+)$")) or path
end

-- Whether to go ahead with a destination that is already there
local function may_overwrite(path)
	if not stat.lstat(path) then return true end
	if force then
		unistd.unlink(path)
		return true
	end
	if interactive then
		unistd.write(2, "cp: overwrite " .. path .. "? ")
		local answer = io.read("l")
		return answer ~= nil and answer:lower():sub(1, 1) == "y"
	end
	return true
end

local function copy_attributes(source, dest, st)
	if not preserve then return end
	stat.chmod(dest, st.st_mode & tonumber("7777", 8))
	utime.utime(dest, st.st_mtime, st.st_atime)
	unistd.chown(dest, st.st_uid, st.st_gid)
end

local function copy_file(source, dest, st)
	if not may_overwrite(dest) then return end
	local fd_in, err = fcntl.open(source, fcntl.O_RDONLY)
	if not fd_in then return warn(err or (source .. ": cannot read")) end
	local mode = preserve and (st.st_mode & tonumber("7777", 8)) or tonumber("666", 8)
	local fd_out, werr = fcntl.open(dest,
		fcntl.O_WRONLY | fcntl.O_CREAT | fcntl.O_TRUNC, mode)
	if not fd_out then
		unistd.close(fd_in)
		return warn(werr or (dest .. ": cannot create"))
	end
	while true do
		local data = unistd.read(fd_in, 65536)
		if not data or data == "" then break end
		unistd.write(fd_out, data)
	end
	unistd.close(fd_in)
	unistd.close(fd_out)
	copy_attributes(source, dest, st)
end

local copy

local function copy_dir(source, dest, st)
	if not stat.stat(dest) then
		local ok, err = stat.mkdir(dest, st.st_mode & tonumber("7777", 8))
		if not ok then return warn(err or (dest .. ": cannot create")) end
	elseif not isdir(dest) then
		return warn(dest .. ": not a directory")
	end
	local names = dirent.dir(source)
	if not names then return warn(source .. ": cannot read") end
	table.sort(names)
	for _, name in ipairs(names) do
		if name ~= "." and name ~= ".." then
			copy(source .. "/" .. name, dest .. "/" .. name)
		end
	end
	copy_attributes(source, dest, st)
end

function copy(source, dest)
	local st = stat.lstat(source)
	if not st then return warn(source .. ": No such file or directory") end

	if stat.S_ISLNK(st.st_mode) ~= 0 and recursive then
		-- a symlink is copied as a symlink, not as what it points at
		if not may_overwrite(dest) then return end
		local to = unistd.readlink(source)
		if not to then return warn(source .. ": cannot read the link") end
		unistd.unlink(dest)
		local ok, err = unistd.link(to, dest, true)
		if not ok then return warn(err or (dest .. ": cannot link")) end
		return
	end

	local full = stat.stat(source)
	if not full then return warn(source .. ": No such file or directory") end

	if stat.S_ISDIR(full.st_mode) ~= 0 then
		if not recursive then
			return warn(source .. ": is a directory")
		end
		return copy_dir(source, dest, full)
	end
	copy_file(source, dest, full)
end

local into_dir = isdir(target)
if #sources > 1 and not into_dir then
	unistd.write(2, "cp: " .. target .. ": not a directory\n")
	os.exit(1)
end

for _, source in ipairs(sources) do
	local dest = into_dir and (target .. "/" .. basename(source)) or target
	copy(source, dest)
end

os.exit(status)
