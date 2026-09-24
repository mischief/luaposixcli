#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
-- stty - report or set terminal modes
local prefix = ((arg[0] or "stty"):match("(.+/)") or "./") .. "../"
package.path = prefix .. "?.lua;" .. prefix .. "share/lua/5.4/?.lua;" .. package.path
if not package.cpath:find("build") then
	package.cpath = prefix .. "build/?.so;" .. prefix .. "lib/lua/5.4/?.so;" .. package.cpath
end

local termio = require("posix.termio")
local unistd = require("posix.unistd")
local sys = require("luaposixcli.sys")

local function die(msg)
	unistd.write(2, "stty: " .. msg .. "\n")
	os.exit(1)
end

-- Which field of the attributes each mode name lives in
local modes = {
	iflag = { "BRKINT", "ICRNL", "IGNBRK", "IGNCR", "IGNPAR", "INLCR",
		"INPCK", "ISTRIP", "IXANY", "IXOFF", "IXON", "PARMRK" },
	oflag = { "OPOST", "ONLCR", "OCRNL", "ONOCR", "ONLRET", "OFILL" },
	cflag = { "CLOCAL", "CREAD", "CSTOPB", "HUPCL", "PARENB", "PARODD" },
	lflag = { "ECHO", "ECHOE", "ECHOK", "ECHONL", "ICANON", "IEXTEN",
		"ISIG", "NOFLSH", "TOSTOP" },
}

local where = {}
for field, names in pairs(modes) do
	for _, name in ipairs(names) do
		if termio[name] then where[name:lower()] = { field = field, bit = termio[name] } end
	end
end

-- The control characters worth naming, and how they are written
local cc_names = {
	{ "intr", "VINTR" }, { "quit", "VQUIT" }, { "erase", "VERASE" },
	{ "kill", "VKILL" }, { "eof", "VEOF" }, { "start", "VSTART" },
	{ "stop", "VSTOP" }, { "susp", "VSUSP" }, { "min", "VMIN" },
	{ "time", "VTIME" },
}

local fd = 0
local args = {}
local show_all = false

local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "-a" or a == "-g" then
		show_all = true
	elseif a == "-F" or a == "--file" then
		i = i + 1
		local path = arg[i] or die("-F needs a file")
		local fcntl = require("posix.fcntl")
		local opened, err = fcntl.open(path, fcntl.O_RDONLY | fcntl.O_NONBLOCK)
		if not opened then die(tostring(err)) end
		fd = opened
	else
		args[#args + 1] = a
	end
	i = i + 1
end

local attrs = termio.tcgetattr(fd)
if not attrs then
	die("standard input is not a terminal")
end

local function ctrl(byte)
	if byte == 0 then return "<undef>" end
	if byte == 127 then return "^?" end
	if byte < 32 then return "^" .. string.char(byte + 64) end
	return string.char(byte)
end

-- A serial console has no window size to report, so fall back to what
-- the environment says, the way every curses program does.
local function winsize()
	local rows, cols = sys.winsize(fd)
	if not rows or rows == 0 or cols == 0 then
		rows = tonumber(os.getenv("LINES")) or rows
		cols = tonumber(os.getenv("COLUMNS")) or cols
	end
	return rows, cols
end

local function report()
	local rows, cols = winsize()
	if rows then
		unistd.write(1, string.format("rows %d; columns %d;\n", rows, cols))
	end
	local parts = {}
	for _, pair in ipairs(cc_names) do
		local name, key = pair[1], pair[2]
		local slot = termio[key]
		if slot and attrs.cc[slot] then
			if name == "min" or name == "time" then
				parts[#parts + 1] = name .. " = " .. attrs.cc[slot]
			else
				parts[#parts + 1] = name .. " = " .. ctrl(attrs.cc[slot])
			end
		end
	end
	unistd.write(1, table.concat(parts, "; ") .. ";\n")

	for _, field in ipairs({ "iflag", "oflag", "cflag", "lflag" }) do
		local out = {}
		for _, name in ipairs(modes[field]) do
			local bit = termio[name]
			if bit then
				local on = (attrs[field] & bit) ~= 0
				if show_all or not on then
					out[#out + 1] = (on and "" or "-") .. name:lower()
				elseif on then
					out[#out + 1] = name:lower()
				end
			end
		end
		if #out > 0 then unistd.write(1, table.concat(out, " ") .. "\n") end
	end
end

-- raw and cooked are the two everyone actually asks for, and each is a
-- handful of the flags above
local function set_raw(on)
	if on then
		attrs.iflag = attrs.iflag & ~(termio.BRKINT | termio.ICRNL | termio.INPCK
			| termio.ISTRIP | termio.IXON)
		attrs.oflag = attrs.oflag & ~termio.OPOST
		attrs.lflag = attrs.lflag & ~(termio.ECHO | termio.ICANON | termio.IEXTEN
			| termio.ISIG)
		attrs.cc[termio.VMIN] = 1
		attrs.cc[termio.VTIME] = 0
	else
		attrs.iflag = attrs.iflag | termio.BRKINT | termio.ICRNL | termio.IXON
		attrs.oflag = attrs.oflag | termio.OPOST
		attrs.lflag = attrs.lflag | termio.ECHO | termio.ICANON | termio.IEXTEN
			| termio.ISIG
	end
end

if #args == 0 then
	report()
	os.exit(0)
end

local changed = false
local n = 1
while n <= #args do
	local word = args[n]
	local off = word:sub(1, 1) == "-"
	local name = off and word:sub(2) or word

	if name == "raw" then
		set_raw(not off)
		changed = true
	elseif name == "cooked" or name == "sane" then
		set_raw(off)
		changed = true
	elseif name == "size" then
		local rows, cols = winsize()
		if not rows then die("cannot get the window size") end
		unistd.write(1, rows .. " " .. cols .. "\n")
	elseif name == "rows" or name == "columns" or name == "cols" then
		n = n + 1
		local value = tonumber(args[n]) or die(name .. " needs a number")
		local rows, cols = winsize()
		rows, cols = rows or 0, cols or 0
		if name == "rows" then rows = value else cols = value end
		local ok, err = sys.setwinsize(fd, rows, cols)
		if not ok then die("cannot set the window size: " .. tostring(err)) end
	elseif where[name] then
		local slot = where[name]
		if off then
			attrs[slot.field] = attrs[slot.field] & ~slot.bit
		else
			attrs[slot.field] = attrs[slot.field] | slot.bit
		end
		changed = true
	else
		-- a control character, written as a name and a value
		local key
		for _, pair in ipairs(cc_names) do
			if pair[1] == name then key = termio[pair[2]] end
		end
		if key then
			n = n + 1
			local value = args[n] or die(name .. " needs a value")
			local byte
			if name == "min" or name == "time" then
				byte = tonumber(value) or die(name .. ": not a number")
			elseif value:sub(1, 1) == "^" and #value == 2 then
				byte = value:byte(2) & 0x1f
			elseif value == "undef" or value == "^-" then
				byte = 0
			else
				byte = value:byte(1) or 0
			end
			attrs.cc[key] = byte
			changed = true
		else
			die("unknown mode: " .. word)
		end
	end
	n = n + 1
end

if changed then
	local ok, err = termio.tcsetattr(fd, termio.TCSANOW, attrs)
	if not ok then die(tostring(err)) end
end
