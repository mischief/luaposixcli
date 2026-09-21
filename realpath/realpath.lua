#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
-- realpath - the path with every link and every . and .. taken out
local prefix = ((arg[0] or "realpath"):match("(.+/)") or "./") .. "../"
package.path = prefix .. "?.lua;" .. prefix .. "share/lua/5.4/?.lua;" .. package.path

local unistd = require("posix.unistd")
local stat = require("posix.sys.stat")
local util = require("luaposixcli.util")

-- the last component need not exist, which is what makes realpath
-- useful for naming a file about to be made. -e demands that it does.
local quiet, must_exist = false, false
local paths = {}

local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "--" then
		for j = i + 1, #arg do paths[#paths + 1] = arg[j] end
		break
	elseif a:sub(1, 1) == "-" and #a > 1 then
		for c in a:sub(2):gmatch(".") do
			if c == "q" then quiet = true
			elseif c == "E" then must_exist = false
			elseif c == "e" then must_exist = true
			else util.die("usage: realpath [-Eeq] file...", 2) end
		end
	else
		paths[#paths + 1] = a
	end
	i = i + 1
end

if #paths == 0 then util.die("usage: realpath [-Eeq] file...", 2) end

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

-- resolve every component, because a link in the middle of the path
-- moves everything after it
local function resolve(path)
	if path:sub(1, 1) ~= "/" then
		path = (unistd.getcwd() or ".") .. "/" .. path
	end
	local done = ""
	local seen = 0
	for part in path:gmatch("[^/]+") do
		if part == "." then
			-- nothing
		elseif part == ".." then
			done = done:match("^(.*)/[^/]*$") or ""
		else
			local try = done .. "/" .. part
			local to = unistd.readlink(try)
			while to do
				seen = seen + 1
				if seen > 40 then return nil, "too many levels of symbolic links" end
				if to:sub(1, 1) == "/" then
					try = normalize(to)
				else
					try = normalize(done .. "/" .. to)
				end
				to = unistd.readlink(try)
			end
			done = try
		end
	end
	return done == "" and "/" or done
end

local status = 0
for _, path in ipairs(paths) do
	local answer, err = resolve(path)
	-- the directory holding it must exist either way: a name under a
	-- directory that is not there names nothing
	if answer and not must_exist then
		local parent = answer:match("^(.*)/[^/]*$")
		if parent and parent ~= "" and not stat.stat(parent) then
			answer, err = nil, "No such file or directory"
		end
	end
	if answer and must_exist and not stat.lstat(answer) then
		answer, err = nil, "No such file or directory"
	end
	if answer then
		unistd.write(1, answer .. "\n")
	else
		if not quiet then
			unistd.write(2, "realpath: " .. path .. ": " .. (err or "cannot resolve") .. "\n")
		end
		status = 1
	end
end
os.exit(status)
