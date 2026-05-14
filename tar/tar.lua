#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
-- tar/tar.lua - POSIX tar CLI frontend
local src_dir = (arg[0]:match("(.+/)") or "./") .. "../"
package.path = src_dir .. "?.lua;" .. package.path

local unistd = require("posix.unistd")
local fcntl = require("posix.fcntl")
local dirent = require("posix.dirent")
local stat = require("posix.sys.stat")
local pwd = require("posix.pwd")
local grp = require("posix.grp")
local format = require("tar.format")

local mode, archive, verbose, files = nil, nil, false, {}

-- Parse arguments: tar [cxtv]f archive [files...]
local flags = arg[1] or ""
if flags:find("c") then mode = "create"
elseif flags:find("x") then mode = "extract"
elseif flags:find("t") then mode = "list"
end
if flags:find("v") then verbose = true end

if flags:find("f") then
	archive = arg[2]
	for i = 3, #arg do files[#files + 1] = arg[i] end
else
	-- f might be separate: tar -cf archive files...
	local i = 1
	while i <= #arg do
		local a = arg[i]
		if a == "-c" then mode = "create"
		elseif a == "-x" then mode = "extract"
		elseif a == "-t" then mode = "list"
		elseif a == "-v" then verbose = true
		elseif a == "-f" then i = i + 1; archive = arg[i]
		elseif a:sub(1, 1) ~= "-" and not archive then
			-- already parsed flags above
			break
		end
		i = i + 1
	end
	for j = i, #arg do files[#files + 1] = arg[j] end
end

if not mode or not archive then
	unistd.write(2, "usage: tar {c|x|t}[v]f archive [file...]\n")
	os.exit(1)
end

-- Recursively add a path to the archive
local function add_path(fd, path)
	local s = stat.lstat(path)
	if not s then
		unistd.write(2, "tar: " .. path .. ": No such file or directory\n")
		return
	end

	local pw = pwd.getpwuid(s.st_uid)
	local gr = grp.getgrgid(s.st_gid)
	local hdr = {
		name = path,
		mode = s.st_mode & 0xFFF,
		uid = s.st_uid,
		gid = s.st_gid,
		size = 0,
		mtime = s.st_mtime,
		uname = pw and pw.pw_name or "",
		gname = gr and gr.gr_name or "",
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
		-- Read file data
		local rfd = fcntl.open(path, fcntl.O_RDONLY)
		local data = ""
		if rfd then
			data = unistd.read(rfd, s.st_size) or ""
			unistd.close(rfd)
		end
		format.write_entry(fd, hdr, data)
		if verbose then unistd.write(2, hdr.name .. "\n") end
	end
end

if mode == "create" then
	if #files == 0 then
		unistd.write(2, "tar: no files to archive\n")
		os.exit(1)
	end
	local fd
	if archive == "-" then
		fd = 1
	else
		fd = fcntl.open(archive, fcntl.O_WRONLY + fcntl.O_CREAT + fcntl.O_TRUNC, 420)
	end
	if not fd then
		unistd.write(2, "tar: cannot open " .. archive .. "\n")
		os.exit(1)
	end
	for _, f in ipairs(files) do
		-- Strip trailing slash for consistency
		add_path(fd, f:gsub("/$", ""))
	end
	unistd.write(fd, format.eof_marker())
	if fd ~= 1 then unistd.close(fd) end

elseif mode == "list" then
	local fd
	if archive == "-" then fd = 0
	else fd = fcntl.open(archive, fcntl.O_RDONLY) end
	if not fd then
		unistd.write(2, "tar: cannot open " .. archive .. "\n")
		os.exit(1)
	end
	while true do
		local hdr = format.read_entry(fd)
		if not hdr then break end
		unistd.write(1, hdr.name .. "\n")
	end
	if fd ~= 0 then unistd.close(fd) end

elseif mode == "extract" then
	local fd
	if archive == "-" then fd = 0
	else fd = fcntl.open(archive, fcntl.O_RDONLY) end
	if not fd then
		unistd.write(2, "tar: cannot open " .. archive .. "\n")
		os.exit(1)
	end
	while true do
		local hdr, data = format.read_entry(fd)
		if not hdr then break end
		if verbose then unistd.write(2, hdr.name .. "\n") end

		if hdr.typeflag == "5" then
			-- Directory
			stat.mkdir(hdr.name, hdr.mode | 0x1C0) -- ensure rwx for owner
		elseif hdr.typeflag == "2" then
			-- Symlink
			unistd.link(hdr.linkname, hdr.name, true)
		elseif hdr.typeflag == "0" or hdr.typeflag == "" then
			-- Regular file: ensure parent directory exists
			local dir = hdr.name:match("(.+)/")
			if dir then stat.mkdir(dir, 493) end -- best effort
			local wfd = fcntl.open(hdr.name, fcntl.O_WRONLY + fcntl.O_CREAT + fcntl.O_TRUNC, hdr.mode)
			if wfd then
				if #data > 0 then unistd.write(wfd, data) end
				unistd.close(wfd)
			end
		end
	end
	if fd ~= 0 then unistd.close(fd) end
end
