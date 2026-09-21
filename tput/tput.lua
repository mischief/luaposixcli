#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
-- tput - write a terminal capability. There is no terminfo database
-- here, so these are the ANSI sequences. TERM unset or dumb reports
-- failure rather than writing nonsense at a terminal that cannot take it.
local prefix = ((arg[0] or "tput"):match("(.+/)") or "./") .. "../"
package.path = prefix .. "?.lua;" .. prefix .. "share/lua/5.4/?.lua;" .. package.path
if not package.cpath:find("build") then
	package.cpath = prefix .. "build/?.so;" .. prefix .. "lib/lua/5.4/?.so;" .. package.cpath
end

local unistd = require("posix.unistd")
local sys = require("luaposixcli.sys")

local ESC = "\27"
local CSI = ESC .. "["

local function die(msg, status)
	unistd.write(2, "tput: " .. msg .. "\n")
	os.exit(status or 2)
end

-- Strings, by both their terminfo and termcap names where they differ
local strings = {
	clear = CSI .. "H" .. CSI .. "2J",
	home = CSI .. "H",
	el = CSI .. "K", ce = CSI .. "K",
	el1 = CSI .. "1K",
	ed = CSI .. "J", cd = CSI .. "J",
	bold = CSI .. "1m", md = CSI .. "1m",
	dim = CSI .. "2m",
	smul = CSI .. "4m", us = CSI .. "4m",
	rmul = CSI .. "24m", ue = CSI .. "24m",
	smso = CSI .. "7m", so = CSI .. "7m",
	rmso = CSI .. "27m", se = CSI .. "27m",
	rev = CSI .. "7m",
	blink = CSI .. "5m",
	sgr0 = CSI .. "0m", me = CSI .. "0m",
	civis = CSI .. "?25l", vi = CSI .. "?25l",
	cnorm = CSI .. "?25h", ve = CSI .. "?25h",
	smcup = CSI .. "?1049h", ti = CSI .. "?1049h",
	rmcup = CSI .. "?1049l", te = CSI .. "?1049l",
	bel = "\7",
	cr = "\r",
	ind = "\n",
}

-- Capabilities that take arguments
local parameterised = {
	cup = function(row, col) return CSI .. (row + 1) .. ";" .. (col + 1) .. "H" end,
	cuu = function(n) return CSI .. n .. "A" end,
	cud = function(n) return CSI .. n .. "B" end,
	cuf = function(n) return CSI .. n .. "C" end,
	cub = function(n) return CSI .. n .. "D" end,
	setaf = function(n) return CSI .. (30 + n) .. "m" end,
	setab = function(n) return CSI .. (40 + n) .. "m" end,
	setf = function(n) return CSI .. (30 + n) .. "m" end,
	setb = function(n) return CSI .. (40 + n) .. "m" end,
}

local booleans = {
	am = true, bce = false, hs = false, km = true, xenl = true,
}

local function size()
	local rows, cols = sys.winsize(1)
	if not rows or rows == 0 or cols == 0 then
		rows = tonumber(os.getenv("LINES")) or rows
		cols = tonumber(os.getenv("COLUMNS")) or cols
	end
	return rows, cols
end

local term = os.getenv("TERM")
local ansi = term ~= nil and term ~= "" and term ~= "dumb"

local args = {}
for _, a in ipairs(arg) do
	if a == "-T" then
		-- the next argument is the terminal name
	elseif a:sub(1, 2) == "-T" then
		term = a:sub(3)
		ansi = term ~= "" and term ~= "dumb"
	else
		args[#args + 1] = a
	end
end

local cap = args[1]
if not cap then
	die("usage: tput [-T type] capability [parameter...]")
end

if cap == "longname" then
	unistd.write(1, (term or "unknown") .. "\n")
	os.exit(0)
end

-- the numbers, which a script asks for far more often than anything else
if cap == "cols" or cap == "columns" then
	local _, cols = size()
	unistd.write(1, tostring(cols or 80) .. "\n")
	os.exit(0)
elseif cap == "lines" then
	local rows = size()
	unistd.write(1, tostring(rows or 24) .. "\n")
	os.exit(0)
elseif cap == "colors" then
	unistd.write(1, ansi and "8\n" or "-1\n")
	os.exit(0)
end

if booleans[cap] ~= nil then
	os.exit(booleans[cap] and 0 or 1)
end

if not ansi then
	die("no terminal: TERM is " .. (term == nil and "not set" or term), 1)
end

if strings[cap] then
	unistd.write(1, strings[cap])
	os.exit(0)
end

if parameterised[cap] then
	local params = {}
	for i = 2, #args do
		params[#params + 1] = tonumber(args[i]) or die(args[i] .. ": not a number")
	end
	if #params == 0 then die(cap .. " needs a parameter") end
	unistd.write(1, parameterised[cap](table.unpack(params)))
	os.exit(0)
end

die("unknown capability: " .. cap, 4)
