#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")

if #arg == 0 then
	io.stderr:write("usage: printf format [argument...]\n")
	os.exit(2)
end

local status = 0

-- Escape sequences understood in the format, and in a %b argument
local function unescape(s, in_arg)
	local out = {}
	local i = 1
	while i <= #s do
		local c = s:sub(i, i)
		if c ~= "\\" or i == #s then
			out[#out + 1] = c
			i = i + 1
		else
			local e = s:sub(i + 1, i + 1)
			i = i + 2
			if e == "n" then out[#out + 1] = "\n"
			elseif e == "t" then out[#out + 1] = "\t"
			elseif e == "r" then out[#out + 1] = "\r"
			elseif e == "a" then out[#out + 1] = "\a"
			elseif e == "b" then out[#out + 1] = "\b"
			elseif e == "f" then out[#out + 1] = "\f"
			elseif e == "v" then out[#out + 1] = "\v"
			elseif e == "\\" then out[#out + 1] = "\\"
			elseif e == "c" and in_arg then return table.concat(out), true
			elseif e == "0" or (in_arg and e:match("%d")) then
				local digits = s:match("^[0-7][0-7]?[0-7]?", in_arg and i - 1 or i)
				if digits then
					if not in_arg then i = i + #digits else i = i - 1 + #digits end
					out[#out + 1] = string.char(tonumber(digits, 8) % 256)
				else
					out[#out + 1] = "\0"
				end
			else
				out[#out + 1] = "\\" .. e
			end
		end
	end
	return table.concat(out), false
end

local function numeric(text)
	local n = tonumber(text)
	if not n then
		io.stderr:write("printf: " .. text .. ": expected numeric value\n")
		status = 1
		return 0
	end
	return n
end

-- Apply the format once. Returns the text and how many operands it used.
local function format_once(fmt, args, first)
	local out = {}
	local used = 0
	local i = 1
	local stop = false
	while i <= #fmt and not stop do
		local c = fmt:sub(i, i)
		if c ~= "%" then
			out[#out + 1] = c
			i = i + 1
		elseif fmt:sub(i + 1, i + 1) == "%" then
			out[#out + 1] = "%"
			i = i + 2
		else
			local flags, width, prec, conv =
				fmt:match("^%%([-+ #0]*)(%d*)(%.?%d*)([diouxXeEfgGaAcsb])", i)
			if not conv then
				out[#out + 1] = c
				i = i + 1
			else
				i = i + 2 + #flags + #width + #prec
				local a = args[first + used]
				used = used + 1
				local spec = "%" .. flags .. width .. prec
				if conv == "b" then
					local text, terminate = unescape(a or "", true)
					out[#out + 1] = string.format(spec .. "s", text)
					if terminate then stop = true end
				elseif conv == "c" then
					out[#out + 1] = string.format(spec .. "s", (a or ""):sub(1, 1))
				elseif conv == "s" then
					out[#out + 1] = string.format(spec .. "s", a or "")
				elseif conv == "u" then
					local n = math.tointeger(numeric(a or "0")) or 0
					out[#out + 1] = string.format(spec .. "d", n < 0 and -n or n)
				elseif conv == "d" or conv == "i" or conv == "o"
					or conv == "x" or conv == "X" then
					local n = math.tointeger(numeric(a or "0")) or 0
					out[#out + 1] = string.format(spec .. (conv == "i" and "d" or conv), n)
				else
					out[#out + 1] = string.format(spec .. conv, numeric(a or "0"))
				end
			end
		end
	end
	return table.concat(out), used, stop
end

local fmt = unescape(arg[1], false)
local args = {}
for i = 2, #arg do args[#args + 1] = arg[i] end

-- POSIX: reuse the format until the operands run out
local first = 1
repeat
	local text, used, stop = format_once(fmt, args, first)
	unistd.write(1, text)
	if stop or used == 0 then break end
	first = first + used
until first > #args

os.exit(status)
