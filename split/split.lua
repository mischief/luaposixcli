#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
-- split - a file in pieces, by lines or by bytes
local prefix = ((arg[0] or "split"):match("(.+/)") or "./") .. "../"
package.path = prefix .. "?.lua;" .. prefix .. "share/lua/5.4/?.lua;" .. package.path

local unistd = require("posix.unistd")
local util = require("luaposixcli.util")

local lines_each, bytes_each = 1000, nil
local suffix_len = 2
local operands = {}

local function usage()
	util.die("usage: split [-l line_count] [-a suffix_length] [-b n[k|m]] [file [prefix]]", 2)
end

local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "--" then
		for j = i + 1, #arg do operands[#operands + 1] = arg[j] end
		break
	elseif a:match("^%-%d+$") then
		lines_each, bytes_each = tonumber(a:sub(2)), nil
	elseif a:sub(1, 2) == "-l" or a:sub(1, 2) == "-b" or a:sub(1, 2) == "-a" then
		local which = a:sub(2, 2)
		local value = a:sub(3)
		if value == "" then
			i = i + 1
			value = arg[i] or usage()
		end
		if which == "l" then
			lines_each, bytes_each = tonumber(value) or usage(), nil
		elseif which == "a" then
			suffix_len = tonumber(value) or usage()
		else
			local n, unit = value:match("^(%d+)([kmKM]?)$")
			if not n then usage() end
			local scale = (unit:lower() == "k" and 1024)
				or (unit:lower() == "m" and 1048576) or 1
			bytes_each, lines_each = tonumber(n) * scale, nil
		end
	elseif a:sub(1, 1) == "-" and #a > 1 then
		usage()
	else
		operands[#operands + 1] = a
	end
	i = i + 1
end

local input = operands[1]
local name = operands[2] or "x"
if input == "-" then input = nil end

local data, err = util.slurp(input)
if not data then util.die(err or (tostring(input) .. ": cannot read")) end

-- aa, ab, ... zz, and then out of names, which is what POSIX says
local function suffix(n)
	local out = {}
	for _ = 1, suffix_len do
		out[#out + 1] = string.char(97 + n % 26)
		n = n // 26
	end
	local s = table.concat(out):reverse()
	if n > 0 then util.die("too many pieces for a " .. suffix_len .. " letter suffix") end
	return s
end

local function write_piece(n, text)
	local path = name .. suffix(n)
	local f, werr = io.open(path, "wb")
	if not f then util.die(werr or (path .. ": cannot write")) end
	f:write(text)
	f:close()
end

local piece = 0
if bytes_each then
	local at = 1
	while at <= #data do
		write_piece(piece, data:sub(at, at + bytes_each - 1))
		at = at + bytes_each
		piece = piece + 1
	end
else
	local held, count = {}, 0
	for line in util.lines(data, true) do
		held[#held + 1] = line
		count = count + 1
		if count == lines_each then
			write_piece(piece, table.concat(held))
			held, count = {}, 0
			piece = piece + 1
		end
	end
	if #held > 0 then write_piece(piece, table.concat(held)) end
end
