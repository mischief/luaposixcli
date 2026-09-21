#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
-- strings - the printable runs in a file
local prefix = ((arg[0] or "strings"):match("(.+/)") or "./") .. "../"
package.path = prefix .. "?.lua;" .. prefix .. "share/lua/5.4/?.lua;" .. package.path

local unistd = require("posix.unistd")
local util = require("luaposixcli.util")

local min = 4
local radix = nil
local files = {}

local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "--" then
		for j = i + 1, #arg do files[#files + 1] = arg[j] end
		break
	elseif a:match("^%-%d+$") then
		min = tonumber(a:sub(2))
	elseif a:sub(1, 2) == "-n" or a:sub(1, 2) == "-t" then
		local which = a:sub(2, 2)
		local value = a:sub(3)
		if value == "" then
			i = i + 1
			value = arg[i]
		end
		if not value then util.die("usage: strings [-a] [-n number] [-t d|o|x] [file...]") end
		if which == "n" then
			min = tonumber(value) or util.die("bad length: " .. value)
		else
			if not value:match("^[dox]$") then util.die("bad radix: " .. value) end
			radix = value
		end
	elseif a == "-a" then
		-- the whole file is what we read anyway
	elseif a:sub(1, 1) == "-" and #a > 1 then
		util.die("usage: strings [-a] [-n number] [-t d|o|x] [file...]")
	else
		files[#files + 1] = a
	end
	i = i + 1
end

local formats = { d = "%d", o = "%o", x = "%x" }

local function scan(data, name)
	local run, start = {}, 0
	local function flush(at)
		if #run >= min then
			local text = table.concat(run)
			if name then unistd.write(1, name .. ": ") end
			if radix then
				unistd.write(1, string.format(formats[radix] .. " ", start))
			end
			unistd.write(1, text .. "\n")
		end
		run = {}
		start = at
	end
	for at = 1, #data do
		local b = data:byte(at)
		-- printable, plus tab, is what makes a string worth showing
		if (b >= 32 and b < 127) or b == 9 then
			if #run == 0 then start = at - 1 end
			run[#run + 1] = string.char(b)
		else
			flush(at)
		end
	end
	flush(#data)
end

if #files == 0 then
	scan(util.slurp_fd(0) or "", nil)
else
	for _, path in ipairs(files) do
		local data, err = util.slurp(path)
		if not data then
			util.warn(err or (path .. ": cannot read"))
		else
			scan(data, #files > 1 and path or nil)
		end
	end
end
