#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")

local delim = "\t"
local fields = nil
local chars = nil
local files = {}

local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "-d" then i = i + 1; delim = arg[i]
	elseif a == "-f" then i = i + 1; fields = arg[i]
	elseif a == "-c" then i = i + 1; chars = arg[i]
	elseif a:match("^%-d.") then delim = a:sub(3)
	elseif a:match("^%-f.") then fields = a:sub(3)
	elseif a:match("^%-c.") then chars = a:sub(3)
	else files[#files + 1] = a end
	i = i + 1
end

-- parse range spec like "1,3" or "2-4" or "1-"
local function parse_spec(spec)
	local set = {}
	for part in spec:gmatch("[^,]+") do
		local a, b = part:match("^(%d+)%-(%d*)$")
		if a then
			a = tonumber(a)
			b = b ~= "" and tonumber(b) or 9999
			for n = a, b do set[n] = true end
		else
			set[tonumber(part)] = true
		end
	end
	return set
end

-- read input
local content = ""
if #files == 0 or files[1] == "-" then
	while true do
		local data = unistd.read(0, 8192)
		if not data or data == "" then break end
		content = content .. data
	end
else
	local fcntl = require("posix.fcntl")
	local fd = fcntl.open(files[1], fcntl.O_RDONLY)
	if not fd then unistd.write(2, "cut: " .. files[1] .. ": No such file\n"); os.exit(1) end
	while true do
		local data = unistd.read(fd, 8192)
		if not data or data == "" then break end
		content = content .. data
	end
	unistd.close(fd)
end

for line in content:gmatch("([^\n]*)\n?") do
	if line == "" and not content:find("\n$") then break end
	if fields then
		local set = parse_spec(fields)
		local parts = {}
		local n = 0
		for field in (line .. delim):gmatch("([^" .. delim:gsub("%%", "%%%%") .. "]*)" .. delim:gsub("%%", "%%%%")) do
			n = n + 1
			if set[n] then parts[#parts + 1] = field end
		end
		unistd.write(1, table.concat(parts, delim) .. "\n")
	elseif chars then
		local set = parse_spec(chars)
		local out = {}
		for c = 1, #line do
			if set[c] then out[#out + 1] = line:sub(c, c) end
		end
		unistd.write(1, table.concat(out) .. "\n")
	end
end
