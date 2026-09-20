#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local fcntl = require("posix.fcntl")

local gnumeric, greverse, gblanks, gfold = false, false, false, false
local unique = false
local sep = nil
local keys = {}
local files = {}

local function usage()
	unistd.write(2, "usage: sort [-bfnru] [-t char] [-k keydef] [file...]\n")
	os.exit(2)
end

-- A key is field_start[.char][opts][,field_end[.char][opts]], as POSIX
-- spells it: -k2 sorts from field 2 to the end of the line, -k2,2 on
-- field 2 alone, and the letters after either number are that key's own
-- ordering options.
local function parse_key(spec)
	local function part(text)
		local field, char, opts = text:match("^(%d+)%.?(%d*)([bdfginr]*)$")
		if not field then return nil end
		return {
			field = tonumber(field),
			char = tonumber(char),
			numeric = opts:find("n") ~= nil,
			reverse = opts:find("r") ~= nil,
			blanks = opts:find("b") ~= nil,
			fold = opts:find("f") ~= nil,
		}
	end
	local first, second = spec:match("^([^,]+),(.+)$")
	local start = part(first or spec)
	if not start then return nil end
	local stop = second and part(second)
	if second and not stop then return nil end
	-- an option written on either end belongs to the whole key
	local function either(name)
		return start[name] or (stop and stop[name]) or false
	end
	return {
		start = start,
		stop = stop,
		numeric = either("numeric"),
		reverse = either("reverse"),
		blanks = either("blanks"),
		fold = either("fold"),
	}
end

local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "--" then
		for j = i + 1, #arg do files[#files + 1] = arg[j] end
		break
	elseif a:sub(1, 1) == "-" and #a > 1 then
		local j = 2
		while j <= #a do
			local c = a:sub(j, j)
			if c == "n" then gnumeric = true
			elseif c == "r" then greverse = true
			elseif c == "b" then gblanks = true
			elseif c == "f" then gfold = true
			elseif c == "u" then unique = true
			elseif c == "k" or c == "t" then
				-- the value is the rest of this argument, or the next one
				local value = a:sub(j + 1)
				if value == "" then
					i = i + 1
					value = arg[i]
				end
				if not value then usage() end
				if c == "t" then
					sep = value
				else
					local k = parse_key(value)
					if not k then usage() end
					keys[#keys + 1] = k
				end
				j = #a
			else
				usage()
			end
			j = j + 1
		end
	else
		files[#files + 1] = a
	end
	i = i + 1
end

-- read input
local content = ""
if #files == 0 then
	while true do
		local data = unistd.read(0, 8192)
		if not data or data == "" then
			break
		end
		content = content .. data
	end
else
	for _, f in ipairs(files) do
		local fd = fcntl.open(f, fcntl.O_RDONLY)
		if not fd then
			unistd.write(2, "sort: " .. f .. ": No such file or directory\n")
			os.exit(1)
		end
		while true do
			local data = unistd.read(fd, 8192)
			if not data or data == "" then
				break
			end
			content = content .. data
		end
		unistd.close(fd)
	end
end

-- split into lines
local lines = {}
for line in content:gmatch("([^\n]*)\n?") do
	if line ~= "" or content:sub(-1) == "\n" then
		lines[#lines + 1] = line
	end
end
-- remove trailing empty line if input ended with \n
if #lines > 0 and lines[#lines] == "" then
	table.remove(lines)
end

-- Fields of a line. Without -t they are runs of non-blanks; with it,
-- whatever lies between separator characters.
local function fields(line)
	local out = {}
	if sep then
		local pos = 1
		while true do
			local at = line:find(sep, pos, true)
			if not at then
				out[#out + 1] = line:sub(pos)
				break
			end
			out[#out + 1] = line:sub(pos, at - 1)
			pos = at + #sep
		end
	else
		for field in line:gmatch("%S+") do out[#out + 1] = field end
	end
	return out
end

-- The text one key selects from a line
local function key_text(line, key)
	local f = fields(line)
	local first = f[key.start.field]
	if not first then return "" end
	if key.start.char and key.start.char > 1 then
		first = first:sub(key.start.char)
	end
	if not key.stop then
		local rest = { first }
		for n = key.start.field + 1, #f do rest[#rest + 1] = f[n] end
		return table.concat(rest, sep or " ")
	end
	local last = key.stop.field
	if last <= key.start.field then
		if key.stop.char then first = first:sub(1, key.stop.char) end
		return first
	end
	local rest = { first }
	for n = key.start.field + 1, last do
		local text = f[n]
		if not text then break end
		if n == last and key.stop.char then text = text:sub(1, key.stop.char) end
		rest[#rest + 1] = text
	end
	return table.concat(rest, sep or " ")
end

local function compare_text(a, b, numeric, blanks, fold)
	if blanks then
		a, b = a:gsub("^%s+", ""), b:gsub("^%s+", "")
	end
	if numeric then
		-- a numeric key is whatever number the text starts with, so a
		-- key that runs to the end of the line still compares
		local function value(text)
			return tonumber(text:match("^%s*[-+]?%d*%.?%d*")) or 0
		end
		local na, nb = value(a), value(b)
		if na == nb then return 0 end
		return na < nb and -1 or 1
	end
	if fold then a, b = a:upper(), b:upper() end
	if a == b then return 0 end
	return a < b and -1 or 1
end

-- What the ordering options say about two lines, and nothing else: -u
-- calls two lines duplicates exactly when this says they are equal.
local function compare_keys(a, b)
	if #keys == 0 then
		local c = compare_text(a, b, gnumeric, gblanks, gfold)
		if greverse then return -c end
		return c
	end
	for _, key in ipairs(keys) do
		local c = compare_text(key_text(a, key), key_text(b, key),
			key.numeric or gnumeric, key.blanks or gblanks,
			key.fold or gfold)
		if c ~= 0 then
			if key.reverse or greverse then return -c end
			return c
		end
	end
	return 0
end

-- Lines the keys call equal fall back to the whole line, byte for byte,
-- so the order is the same every run. With -u there is no such fallback:
-- those lines are duplicates, and the first one in the input wins.
local order = {}
for n, line in ipairs(lines) do order[line] = order[line] or n end

table.sort(lines, function(a, b)
	local c = compare_keys(a, b)
	if c ~= 0 then return c < 0 end
	if not unique then
		local plain = compare_text(a, b, false, false, false)
		if greverse then plain = -plain end
		if plain ~= 0 then return plain < 0 end
	end
	return (order[a] or 0) < (order[b] or 0)
end)

if unique then
	local out = {}
	for _, line in ipairs(lines) do
		if #out == 0 or compare_keys(out[#out], line) ~= 0 then
			out[#out + 1] = line
		end
	end
	lines = out
end

for _, line in ipairs(lines) do
	unistd.write(1, line .. "\n")
end
