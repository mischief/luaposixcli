#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")

local symbolic = false
local files = {}
for _, a in ipairs(arg) do
	if a == "-s" then
		symbolic = true
	else
		files[#files + 1] = a
	end
end

if #files < 2 then
	unistd.write(2, "ln: missing operand\n")
	os.exit(1)
end

local target = files[1]
local linkname = files[2]
local ok, err
if symbolic then
	ok, err = unistd.link(target, linkname, true)
else
	ok, err = unistd.link(target, linkname)
end
if ok ~= 0 and err then
	unistd.write(2, "ln: " .. err .. "\n")
	os.exit(1)
end
