#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
-- readlink - what a symbolic link points at
local prefix = ((arg[0] or "readlink"):match("(.+/)") or "./") .. "../"
package.path = prefix .. "?.lua;" .. prefix .. "share/lua/5.4/?.lua;" .. package.path

local unistd = require("posix.unistd")
local stat = require("posix.sys.stat")

local newline, follow, quiet = true, false, false
local files = {}

local function usage()
	unistd.write(2, "usage: readlink [-fn] file...\n")
	os.exit(2)
end

local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "--" then
		for j = i + 1, #arg do files[#files + 1] = arg[j] end
		break
	elseif a:sub(1, 1) == "-" and #a > 1 then
		for c in a:sub(2):gmatch(".") do
			if c == "n" then newline = false
			elseif c == "f" or c == "e" or c == "m" then follow = true
			elseif c == "q" or c == "s" then quiet = true
			else usage() end
		end
	else
		files[#files + 1] = a
	end
	i = i + 1
end

if #files == 0 then usage() end

-- . and .. taken out, so the answer is one path rather than a route
local function normalize(path)
	local parts = {}
	for part in path:gmatch("[^/]+") do
		if part == ".." then
			parts[#parts] = nil
		elseif part ~= "." then
			parts[#parts + 1] = part
		end
	end
	return "/" .. table.concat(parts, "/")
end

-- -f resolves the whole path, link by link, and answers absolutely: the
-- point of it is a name that means the same thing from anywhere.
local function resolve(path)
	if path:sub(1, 1) ~= "/" then
		path = (unistd.getcwd() or ".") .. "/" .. path
	end
	path = normalize(path)
	local seen = 0
	while seen < 40 do
		local to = unistd.readlink(path)
		if not to then return path end
		if to:sub(1, 1) ~= "/" then
			to = (path:match("^(.*)/[^/]*$") or "") .. "/" .. to
		end
		path = normalize(to)
		seen = seen + 1
	end
	return path
end

local status = 0
for _, path in ipairs(files) do
	local answer
	if follow then
		answer = resolve(path)
		if not stat.lstat(answer) then answer = nil end
	else
		answer = unistd.readlink(path)
	end
	if answer then
		unistd.write(1, answer .. (newline and "\n" or ""))
	else
		if not quiet then
			unistd.write(2, "readlink: " .. path .. ": not a symbolic link\n")
		end
		status = 1
	end
end
os.exit(status)
