#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local dirent = require("posix.dirent")
local stat = require("posix.sys.stat")
local fnmatch = require("posix.fnmatch")

local paths = {}
local predicates = {}
local optind = 1

-- Parse arguments: paths come first, then expressions starting with - or ( or !
while optind <= #arg do
	local a = arg[optind]
	if a:sub(1, 1) == "-" or a == "(" or a == ")" or a == "!" then break end
	paths[#paths + 1] = a
	optind = optind + 1
end
if #paths == 0 then paths[1] = "." end

-- Parse predicates
while optind <= #arg do
	local a = arg[optind]; optind = optind + 1
	if a == "-name" then
		local pat = arg[optind]; optind = optind + 1
		predicates[#predicates + 1] = { type = "name", pat = pat }
	elseif a == "-type" then
		local t = arg[optind]; optind = optind + 1
		predicates[#predicates + 1] = { type = "type", val = t }
	elseif a == "-print" then
		predicates[#predicates + 1] = { type = "print" }
	elseif a == "-maxdepth" then
		local d = tonumber(arg[optind]); optind = optind + 1
		predicates[#predicates + 1] = { type = "maxdepth", val = d }
	elseif a == "-mindepth" then
		local d = tonumber(arg[optind]); optind = optind + 1
		predicates[#predicates + 1] = { type = "mindepth", val = d }
	elseif a == "-newer" then
		local ref = arg[optind]; optind = optind + 1
		local rs = stat.stat(ref)
		predicates[#predicates + 1] = { type = "newer", mtime = rs and rs.st_mtime or 0 }
	elseif a == "-size" then
		local s = arg[optind]; optind = optind + 1
		predicates[#predicates + 1] = { type = "size", spec = s }
	elseif a == "-exec" then
		local cmd = {}
		while optind <= #arg and arg[optind] ~= ";" do
			cmd[#cmd + 1] = arg[optind]; optind = optind + 1
		end
		optind = optind + 1 -- skip ;
		predicates[#predicates + 1] = { type = "exec", cmd = cmd }
	end
end

-- If no action predicate, add implicit -print
local has_action = false
for _, p in ipairs(predicates) do
	if p.type == "print" or p.type == "exec" then has_action = true end
end
if not has_action then predicates[#predicates + 1] = { type = "print" } end

local maxdepth, mindepth = math.huge, 0
for _, p in ipairs(predicates) do
	if p.type == "maxdepth" then maxdepth = p.val end
	if p.type == "mindepth" then mindepth = p.val end
end

local function file_type(mode)
	if stat.S_ISREG(mode) ~= 0 then return "f"
	elseif stat.S_ISDIR(mode) ~= 0 then return "d"
	elseif stat.S_ISLNK(mode) ~= 0 then return "l"
	elseif stat.S_ISBLK(mode) ~= 0 then return "b"
	elseif stat.S_ISCHR(mode) ~= 0 then return "c"
	elseif stat.S_ISFIFO(mode) ~= 0 then return "p"
	elseif stat.S_ISSOCK(mode) ~= 0 then return "s"
	end
	return "f"
end

local function check_size(s, spec)
	local num, unit = spec:match("^([+-]?%d+)([bcwkMG]?)$")
	if not num then return true end
	num = tonumber(num)
	local bytes = s.st_size
	local blocks
	if unit == "c" then blocks = bytes
	elseif unit == "k" then blocks = math.ceil(bytes / 1024)
	elseif unit == "M" then blocks = math.ceil(bytes / (1024 * 1024))
	else blocks = math.ceil(bytes / 512) end
	if spec:sub(1, 1) == "+" then return blocks > math.abs(num)
	elseif spec:sub(1, 1) == "-" then return blocks < math.abs(num)
	else return blocks == num end
end

local function basename(path)
	return path:match("([^/]+)$") or path
end

local function visit(path, depth)
	if depth > maxdepth then return end
	local s = stat.lstat(path)
	if not s then return end

	-- Evaluate predicates
	local match = true
	for _, p in ipairs(predicates) do
		if p.type == "name" then
			if fnmatch.fnmatch(p.pat, basename(path)) ~= 0 then match = false end
		elseif p.type == "type" then
			if file_type(s.st_mode) ~= p.val then match = false end
		elseif p.type == "newer" then
			if s.st_mtime <= p.mtime then match = false end
		elseif p.type == "size" then
			if not check_size(s, p.spec) then match = false end
		end
	end

	-- Actions
	if match and depth >= mindepth then
		for _, p in ipairs(predicates) do
			if p.type == "print" then
				unistd.write(1, path .. "\n")
			elseif p.type == "exec" then
				local cmd = {}
				for _, c in ipairs(p.cmd) do
					cmd[#cmd + 1] = c == "{}" and path or c
				end
				os.execute(table.concat(cmd, " "))
			end
		end
	end

	-- Recurse into directories
	if stat.S_ISDIR(s.st_mode) ~= 0 then
		local entries = dirent.dir(path)
		if entries then
			table.sort(entries)
			for _, name in ipairs(entries) do
				if name ~= "." and name ~= ".." then
					local child = path == "/" and "/" .. name or path .. "/" .. name
					visit(child, depth + 1)
				end
			end
		end
	end
end

for _, p in ipairs(paths) do
	visit(p, 0)
end
