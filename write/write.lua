#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
-- write - send what is typed here to somebody else's terminal
local prefix = ((arg[0] or "write"):match("(.+/)") or "./") .. "../"
package.path = prefix .. "?.lua;" .. prefix .. "share/lua/5.4/?.lua;" .. package.path

local unistd = require("posix.unistd")
local stat = require("posix.sys.stat")
local utmp = require("luaposixcli.utmp")
local util = require("luaposixcli.util")

local function usage()
	util.die("usage: write user [terminal]", 2)
end

local optind = 1
for opt, _, oi in unistd.getopt(arg, "") do
	if opt == "?" then usage() end
	optind = oi
end
local operands = util.operands(arg, optind)
if #operands < 1 or #operands > 2 then usage() end

local who, line = operands[1], operands[2]

-- Where that person is. With no terminal named, the one they logged
-- into most recently, which is where they are most likely reading.
local function find_terminal()
	local best = nil
	for _, rec in ipairs(utmp.users()) do
		if rec.user == who then
			if line then
				if rec.line == line then return rec end
			elseif not best or rec.time > best.time then
				best = rec
			end
		end
	end
	return best
end

local rec = find_terminal()
if not rec then
	if line then util.die(who .. " is not logged in on " .. line) end
	util.die(who .. " is not logged in")
end

local path = "/dev/" .. rec.line
local st = stat.stat(path)
if not st then util.die(path .. ": cannot write") end

-- mesg n clears the group write bit, and that is the whole of the
-- permission system here. Root writes to anybody.
if (st.st_mode & stat.S_IWGRP) == 0 and unistd.getuid() ~= 0 then
	util.die(who .. " has messages turned off")
end

local out, err = io.open(path, "w")
if not out then util.die(tostring(err)) end

local from = os.getenv("USER") or os.getenv("LOGNAME") or tostring(unistd.getuid())
local here = unistd.ttyname(0)
here = here and here:gsub("^/dev/", "") or "?"

out:write(string.format("\a\nMessage from %s on %s at %s ...\n",
	from, here, os.date("%H:%M")))
out:flush()

for text in io.lines() do
	out:write(text, "\n")
	out:flush()
end

out:write("EOF\n")
out:close()
