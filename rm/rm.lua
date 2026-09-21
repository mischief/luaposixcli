#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local stat = require("posix.sys.stat")
local dirent = require("posix.dirent")

local force, interactive, recursive = false, false, false
local optind = 1

for opt, _, oi in unistd.getopt(arg, "fiRr") do
	if opt == "f" then force = true; interactive = false
	elseif opt == "i" then interactive = true; force = false
	elseif opt == "R" or opt == "r" then recursive = true
	else
		unistd.write(2, "usage: rm [-fiRr] file...\n")
		os.exit(2)
	end
	optind = oi
end
if arg[optind] == "--" then optind = optind + 1 end

local files = {}
for i = optind, #arg do files[#files + 1] = arg[i] end

if #files == 0 then
	if force then os.exit(0) end
	unistd.write(2, "usage: rm [-fiRr] file...\n")
	os.exit(2)
end

local status = 0

local function confirm(what, path)
	if not interactive then return true end
	unistd.write(2, "rm: remove " .. what .. " " .. path .. "? ")
	local answer = io.read("l")
	return answer ~= nil and answer:lower():sub(1, 1) == "y"
end

local function remove(path)
	local st = stat.lstat(path)
	if not st then
		if not force then
			unistd.write(2, "rm: " .. path .. ": No such file or directory\n")
			status = 1
		end
		return
	end

	if stat.S_ISDIR(st.st_mode) ~= 0 then
		if not recursive then
			unistd.write(2, "rm: " .. path .. ": is a directory\n")
			status = 1
			return
		end
		if not confirm("directory", path) then return end
		local names = dirent.dir(path)
		for _, name in ipairs(names or {}) do
			if name ~= "." and name ~= ".." then
				remove(path .. "/" .. name)
			end
		end
		local ok, err = unistd.rmdir(path)
		if ok ~= 0 then
			unistd.write(2, "rm: " .. (err or path .. ": cannot remove") .. "\n")
			status = 1
		end
		return
	end

	if not confirm("file", path) then return end
	local ok, err = os.remove(path)
	if not ok then
		unistd.write(2, "rm: " .. (err or path .. ": cannot remove") .. "\n")
		status = 1
	end
end

for _, path in ipairs(files) do remove(path) end
os.exit(status)
