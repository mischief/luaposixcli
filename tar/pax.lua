#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
-- tar/pax.lua - POSIX pax (portable archive exchange) using tar/format
local src_dir = (arg[0]:match("(.+/)") or "./") .. "../"
package.path = src_dir .. "?.lua;" .. package.path

local unistd = require("posix.unistd")
local fcntl = require("posix.fcntl")
local dirent = require("posix.dirent")
local stat = require("posix.sys.stat")
local pwd = require("posix.pwd")
local grp = require("posix.grp")
local format = require("tar.format")

local mode = "list" -- default: list (read from stdin, list to stdout)
local verbose = false
local archive_file = nil -- nil means stdin/stdout
local files = {}

local optind = 1
for opt, optarg, oi in unistd.getopt(arg, "rwvf:") do
	if opt == "r" then
		mode = mode == "write" and "copy" or "read"
	elseif opt == "w" then
		mode = mode == "read" and "copy" or "write"
	elseif opt == "v" then verbose = true
	elseif opt == "f" then archive_file = optarg
	end
	optind = oi
end
for i = optind, #arg do files[#files + 1] = arg[i] end

-- Shared: safe path check (same as tar)
local function safe_path(name)
	name = name:gsub("^/+", "")
	if name == "" then return nil end
	for comp in name:gmatch("[^/]+") do
		if comp == ".." then return nil end
	end
	return name
end

local function check_no_symlink_escape(name)
	local path = ""
	for comp in name:gmatch("[^/]+") do
		path = path == "" and comp or path .. "/" .. comp
		local s = stat.lstat(path)
		if s and stat.S_ISLNK(s.st_mode) ~= 0 then return false end
	end
	return true
end

local function safe_symlink(name, target)
	if target:sub(1, 1) == "/" then return false end
	local link_dir = name:match("(.+)/") or ""
	local parts = {}
	for comp in (link_dir .. "/" .. target):gmatch("[^/]+") do
		if comp == ".." then
			if #parts == 0 then return false end
			parts[#parts] = nil
		elseif comp ~= "." then
			parts[#parts + 1] = comp
		end
	end
	return true
end

-- Extract entries from archive fd
local function extract(fd)
	while true do
		local hdr, data = format.read_entry(fd)
		if not hdr then break end
		local name = safe_path(hdr.name)
		if not name then
			unistd.write(2, "pax: skipping unsafe path: " .. hdr.name .. "\n")
		else
			if verbose then unistd.write(2, name .. "\n") end
			if hdr.typeflag == "5" then
				stat.mkdir(name, hdr.mode | 0x1C0)
			elseif hdr.typeflag == "2" then
				if safe_symlink(name, hdr.linkname) then
					unistd.link(hdr.linkname, name, true)
				else
					unistd.write(2, "pax: skipping unsafe symlink: " .. name .. "\n")
				end
			elseif hdr.typeflag == "0" or hdr.typeflag == "" then
				if check_no_symlink_escape(name) then
					local dir = name:match("(.+)/")
					if dir then stat.mkdir(dir, 493) end
					local wfd = fcntl.open(name, fcntl.O_WRONLY + fcntl.O_CREAT + fcntl.O_TRUNC, hdr.mode)
					if wfd then
						if #data > 0 then unistd.write(wfd, data) end
						unistd.close(wfd)
					end
				else
					unistd.write(2, "pax: skipping (symlink in path): " .. name .. "\n")
				end
			end
		end
	end
end

-- List entries from archive fd
local function list(fd)
	while true do
		local hdr = format.read_entry(fd)
		if not hdr then break end
		if verbose then
			local t = hdr.typeflag == "5" and "d" or (hdr.typeflag == "2" and "l" or "-")
			unistd.write(1, string.format("%s %7d %s\n", t, hdr.size, hdr.name))
		else
			unistd.write(1, hdr.name .. "\n")
		end
	end
end

-- Write files to archive fd
local function add_path(fd, path)
	local s = stat.lstat(path)
	if not s then
		unistd.write(2, "pax: " .. path .. ": No such file or directory\n")
		return
	end
	local pw = pwd.getpwuid(s.st_uid)
	local gr = grp.getgrgid(s.st_gid)
	local hdr = {
		name = path, mode = s.st_mode & 0xFFF,
		uid = s.st_uid, gid = s.st_gid, size = 0,
		mtime = s.st_mtime,
		uname = pw and pw.pw_name or "", gname = gr and gr.gr_name or "",
	}
	if stat.S_ISDIR(s.st_mode) ~= 0 then
		hdr.typeflag = "5"
		if hdr.name:sub(-1) ~= "/" then hdr.name = hdr.name .. "/" end
		format.write_entry(fd, hdr, "")
		if verbose then unistd.write(2, hdr.name .. "\n") end
		local entries = dirent.dir(path)
		if entries then
			table.sort(entries)
			for _, name in ipairs(entries) do
				if name ~= "." and name ~= ".." then
					add_path(fd, path .. "/" .. name)
				end
			end
		end
	elseif stat.S_ISLNK(s.st_mode) ~= 0 then
		hdr.typeflag = "2"
		hdr.linkname = unistd.readlink(path) or ""
		format.write_entry(fd, hdr, "")
		if verbose then unistd.write(2, hdr.name .. "\n") end
	elseif stat.S_ISREG(s.st_mode) ~= 0 then
		hdr.typeflag = "0"
		hdr.size = s.st_size
		local rfd = fcntl.open(path, fcntl.O_RDONLY)
		local data = rfd and unistd.read(rfd, s.st_size) or ""
		if rfd then unistd.close(rfd) end
		format.write_entry(fd, hdr, data)
		if verbose then unistd.write(2, hdr.name .. "\n") end
	end
end

if mode == "read" then
	local fd = archive_file and fcntl.open(archive_file, fcntl.O_RDONLY) or 0
	if not fd then unistd.write(2, "pax: cannot open " .. archive_file .. "\n"); os.exit(1) end
	extract(fd)
	if fd ~= 0 then unistd.close(fd) end

elseif mode == "write" then
	local fd = archive_file and fcntl.open(archive_file, fcntl.O_WRONLY + fcntl.O_CREAT + fcntl.O_TRUNC, 420) or 1
	if not fd then unistd.write(2, "pax: cannot open " .. archive_file .. "\n"); os.exit(1) end
	if #files == 0 then
		-- Read file list from stdin
		for line in io.lines() do files[#files + 1] = line end
	end
	for _, f in ipairs(files) do add_path(fd, f:gsub("/$", "")) end
	unistd.write(fd, format.eof_marker())
	if fd ~= 1 then unistd.close(fd) end

elseif mode == "list" then
	local fd = archive_file and fcntl.open(archive_file, fcntl.O_RDONLY) or 0
	if not fd then unistd.write(2, "pax: cannot open " .. archive_file .. "\n"); os.exit(1) end
	list(fd)
	if fd ~= 0 then unistd.close(fd) end

elseif mode == "copy" then
	-- pax -rw: copy files to directory (last argument)
	if #files < 2 then
		unistd.write(2, "usage: pax -rw [file...] directory\n"); os.exit(1)
	end
	local dest = table.remove(files)
	-- Create a tar in memory and extract to dest
	local r, w = unistd.pipe()
	local pid = unistd.fork()
	if pid == 0 then
		unistd.close(r)
		for _, f in ipairs(files) do add_path(w, f:gsub("/$", "")) end
		unistd.write(w, format.eof_marker())
		unistd.close(w)
		os.exit(0)
	else
		unistd.close(w)
		local old = unistd.getcwd()
		unistd.chdir(dest)
		extract(r)
		unistd.close(r)
		unistd.chdir(old)
		require("posix.sys.wait").wait(pid)
	end
end
