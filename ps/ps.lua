#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local prefix = ((arg[0] or "ps"):match("(.+/)") or "./") .. "../"
package.path = prefix .. "?.lua;" .. prefix .. "share/lua/5.4/?.lua;" .. package.path

local unistd = require("posix.unistd")
local list = require("ps.list")

local all = false
local full = false

for _, a in ipairs(arg) do
	for i = 2, #a do
		local c = a:sub(i, i)
		if c == "A" or c == "e" then all = true
		elseif c == "f" then full = true
		end
	end
end

local myuid = unistd.getuid()

local procs, err = list.procs()
if not procs then
	io.stderr:write("ps: " .. err .. "\n")
	os.exit(1)
end

unistd.write(1, list.header(full) .. "\n")

for _, p in ipairs(procs) do
	local show = all or (p.uid == myuid and list.tty(p.tty_nr) ~= "?")
	if show then
		unistd.write(1, list.line(p, full) .. "\n")
	end
end
