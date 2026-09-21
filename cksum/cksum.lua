#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
-- cksum - the POSIX CRC of a file, its size, and its name
local prefix = ((arg[0] or "cksum"):match("(.+/)") or "./") .. "../"
package.path = prefix .. "?.lua;" .. prefix .. "share/lua/5.4/?.lua;" .. package.path

local unistd = require("posix.unistd")
local util = require("luaposixcli.util")

-- The polynomial POSIX names, unreflected, with the length fed through
-- at the end. It is not the CRC anything else calls CRC-32.
local table_crc = {}
do
	for n = 0, 255 do
		local c = n << 24
		for _ = 1, 8 do
			if c & 0x80000000 ~= 0 then
				c = ((c << 1) ~ 0x04c11db7) & 0xffffffff
			else
				c = (c << 1) & 0xffffffff
			end
		end
		table_crc[n] = c
	end
end

local function cksum(data)
	local crc = 0
	for i = 1, #data do
		crc = ((crc << 8) & 0xffffffff) ~ table_crc[((crc >> 24) ~ data:byte(i)) & 0xff]
	end
	local len = #data
	while len > 0 do
		crc = ((crc << 8) & 0xffffffff) ~ table_crc[((crc >> 24) ~ (len & 0xff)) & 0xff]
		len = len >> 8
	end
	return (~crc) & 0xffffffff
end

local files = {}
for _, a in ipairs(arg) do
	if a == "--" then
	elseif a:sub(1, 1) == "-" and #a > 1 then
		util.die("usage: cksum [file...]", 2)
	else
		files[#files + 1] = a
	end
end

local status = 0
if #files == 0 then
	local data = util.slurp_fd(0) or ""
	unistd.write(1, string.format("%d %d\n", cksum(data), #data))
else
	for _, path in ipairs(files) do
		local data, err = util.slurp(path)
		if not data then
			util.warn(err or (path .. ": cannot read"))
			status = 1
		else
			unistd.write(1, string.format("%d %d %s\n", cksum(data), #data, path))
		end
	end
end
os.exit(status)
