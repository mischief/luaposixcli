#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
-- nl - number the lines
local prefix = ((arg[0] or "nl"):match("(.+/)") or "./") .. "../"
package.path = prefix .. "?.lua;" .. prefix .. "share/lua/5.4/?.lua;" .. package.path

local unistd = require("posix.unistd")
local util = require("luaposixcli.util")

local body_style = "t"     -- t numbers the non-empty lines, a all, n none
local increment = 1
local start = 1
local width = 6
local separator = "\t"
local files = {}

local function usage()
	util.die("usage: nl [-b a|t|n] [-i incr] [-v start] [-w width] [-s sep] [file...]", 2)
end

local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "--" then
		for j = i + 1, #arg do files[#files + 1] = arg[j] end
		break
	elseif a:sub(1, 2) == "-b" or a:sub(1, 2) == "-i" or a:sub(1, 2) == "-v"
		or a:sub(1, 2) == "-w" or a:sub(1, 2) == "-s" then
		local which = a:sub(2, 2)
		local value = a:sub(3)
		if value == "" then
			i = i + 1
			value = arg[i] or usage()
		end
		if which == "b" then
			if not value:match("^[atn]$") then usage() end
			body_style = value
		elseif which == "i" then increment = tonumber(value) or usage()
		elseif which == "v" then start = tonumber(value) or usage()
		elseif which == "w" then width = tonumber(value) or usage()
		else separator = value end
	elseif a:sub(1, 1) == "-" and #a > 1 then
		usage()
	else
		files[#files + 1] = a
	end
	i = i + 1
end

local text
if #files == 0 then
	text = util.slurp_fd(0) or ""
else
	local parts = {}
	for _, path in ipairs(files) do
		local data, err = util.slurp(path)
		if not data then util.die(err or (path .. ": cannot read")) end
		parts[#parts + 1] = data
	end
	text = table.concat(parts)
end

local n = start
for line in util.lines(text) do
	local numbered = body_style == "a" or (body_style == "t" and line ~= "")
	if numbered then
		unistd.write(1, string.format("%" .. width .. "d%s%s\n", n, separator, line))
		n = n + increment
	else
		-- an unnumbered line is indented to where the text starts, with
		-- spaces rather than the separator: nothing is being separated
		unistd.write(1, string.rep(" ", width + #separator) .. line .. "\n")
	end
end
