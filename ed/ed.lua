#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
-- ed - line editor
local a = arg or { [0] = "ed" }
local src = a[0]:match("(.+/)") or "./"
local prefix = src .. "../"
package.path = prefix .. "?.lua;" .. prefix .. "share/lua/5.4/?.lua;" .. package.path
if not package.cpath:find("build") then
	package.cpath = prefix .. "build/?.so;" .. prefix .. "lib/lua/5.4/?.so;" .. package.cpath
end

local unistd = require("posix.unistd")
local buffer = require("ed.buffer")

local suppress = false
local prompt = ""
local file = nil

local optind = 1
for opt, optarg, oi in unistd.getopt(a, "sp:") do
	if opt == "s" then suppress = true
	elseif opt == "p" then prompt = optarg
	elseif opt == "?" then
		unistd.write(2, "usage: ed [-s] [-p prompt] [file]\n")
		os.exit(1)
	end
	optind = oi
end

if a[optind] then file = a[optind] end

local ed = buffer.new({ file = file, suppress = suppress, prompt = prompt, ex_mode = false })

if file then
	local ok, result = ed:load(file)
	if ok then
		if not suppress then io.write(result .. "\n") end
	else
		if not suppress then io.stderr:write(result .. "\n") end
	end
end

ed:run()
