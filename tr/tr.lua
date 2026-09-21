#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")

local delete = false
local squeeze = false
local complement = false
local args = {}

local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "--" then
		for j = i + 1, #arg do args[#args + 1] = arg[j] end
		break
	elseif a:sub(1, 1) == "-" and #a > 1 then
		for c in a:sub(2):gmatch(".") do
			if c == "d" then delete = true
			elseif c == "s" then squeeze = true
			elseif c == "c" or c == "C" then complement = true
			else
				unistd.write(2, "usage: tr [-cds] string1 [string2]\n")
				os.exit(2)
			end
		end
	else
		args[#args + 1] = a
	end
	i = i + 1
end

-- expand ranges like a-z, character classes like [:upper:]
local function expand(s)
	-- character classes
	s = s:gsub("%[:upper:%]", "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
	s = s:gsub("%[:lower:%]", "abcdefghijklmnopqrstuvwxyz")
	s = s:gsub("%[:digit:%]", "0123456789")
	s = s:gsub("%[:alpha:%]", "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
	s = s:gsub("%[:alnum:%]", "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
	s = s:gsub("%[:space:%]", " \t\n\r\f\v")
	-- escape sequences
	s = s:gsub("\\n", "\n"):gsub("\\t", "\t"):gsub("\\r", "\r")
	-- ranges
	local result = {}
	local i = 1
	while i <= #s do
		if i + 2 <= #s and s:sub(i + 1, i + 1) == "-" then
			local from = s:byte(i)
			local to = s:byte(i + 2)
			for c = from, to do result[#result + 1] = string.char(c) end
			i = i + 3
		else
			result[#result + 1] = s:sub(i, i)
			i = i + 1
		end
	end
	return table.concat(result)
end

local set1 = expand(args[1] or "")
local set2 = expand(args[2] or "")

-- -c works on everything string1 leaves out. With a replacement, every
-- one of them maps to its last character, which is what tr -c does.
if complement then
	local named = {}
	for n = 1, #set1 do named[set1:sub(n, n)] = true end
	local rest = {}
	for byte = 0, 255 do
		local c = string.char(byte)
		if not named[c] then rest[#rest + 1] = c end
	end
	set1 = table.concat(rest)
	if set2 ~= "" then set2 = string.rep(set2:sub(-1), #set1) end
end

-- build translation/delete table
local map = {}
local squeeze_set = {}
if delete then
	for i = 1, #set1 do map[set1:sub(i, i)] = "" end
elseif set2 ~= "" then
	for i = 1, #set1 do
		local repl = set2:sub(math.min(i, #set2), math.min(i, #set2))
		map[set1:sub(i, i)] = repl
	end
end
if squeeze then
	local sset = (set2 ~= "" and not delete) and set2 or set1
	for i = 1, #sset do squeeze_set[sset:sub(i, i)] = true end
end

local prev = nil
while true do
	local data = unistd.read(0, 8192)
	if not data or data == "" then break end
	local out = {}
	for i = 1, #data do
		local c = data:sub(i, i)
		local r = map[c]
		if r == "" then
			-- deleted
		else
			local ch = r or c
			if squeeze_set[ch] and ch == prev then
				-- squeezed
			else
				out[#out + 1] = ch
				prev = ch
			end
		end
	end
	unistd.write(1, table.concat(out))
end
