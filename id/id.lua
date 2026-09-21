#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local grp = require("posix.grp")
local pwd = require("posix.pwd")

local want = nil        -- "u", "g" or "G"
local names = false     -- -n
local real = false      -- -r
local user = nil

local function usage()
	unistd.write(2, "usage: id [-Ggu] [-nr] [user]\n")
	os.exit(2)
end

local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "--" then
		user = arg[i + 1]
		break
	elseif a:sub(1, 1) == "-" and #a > 1 then
		for c in a:sub(2):gmatch(".") do
			if c == "u" or c == "g" or c == "G" then
				if want and want ~= c then usage() end
				want = c
			elseif c == "n" then names = true
			elseif c == "r" then real = true
			else usage() end
		end
	else
		user = a
	end
	i = i + 1
end

if names and not want then usage() end
if real and not want then usage() end

local uid, gid, groups
if user then
	local entry = pwd.getpwnam(user) or (tonumber(user) and pwd.getpwuid(tonumber(user)))
	if not entry then
		unistd.write(2, "id: " .. user .. ": no such user\n")
		os.exit(1)
	end
	uid, gid = entry.pw_uid, entry.pw_gid
	-- the groups of a named user are the ones that list them, plus their own
	groups = { gid }
	for entry_name in (function()
		local list = {}
		grp.setgrent()
		while true do
			local g = grp.getgrent()
			if not g then break end
			for _, member in ipairs(g.gr_mem or {}) do
				if member == user then list[#list + 1] = g.gr_gid end
			end
		end
		grp.endgrent()
		local n = 0
		return function() n = n + 1; return list[n] end
	end)() do
		groups[#groups + 1] = entry_name
	end
else
	uid = real and unistd.getuid() or unistd.geteuid()
	gid = real and unistd.getgid() or unistd.getegid()
	groups = unistd.getgroups() or { gid }
end

-- the effective group comes first, the way every id prints it
do
	local ordered = { gid }
	for _, g in ipairs(groups) do
		if g ~= gid then ordered[#ordered + 1] = g end
	end
	groups = ordered
end

local function name_of_user(id)
	local entry = pwd.getpwuid(id)
	return entry and entry.pw_name or tostring(id)
end

local function name_of_group(id)
	local entry = grp.getgrgid(id)
	return entry and entry.gr_name or tostring(id)
end

if want == "u" then
	unistd.write(1, (names and name_of_user(uid) or tostring(uid)) .. "\n")
	os.exit(0)
elseif want == "g" then
	unistd.write(1, (names and name_of_group(gid) or tostring(gid)) .. "\n")
	os.exit(0)
elseif want == "G" then
	local out = {}
	for _, g in ipairs(groups) do
		out[#out + 1] = names and name_of_group(g) or tostring(g)
	end
	unistd.write(1, table.concat(out, " ") .. "\n")
	os.exit(0)
end

local gstr = {}
for _, g in ipairs(groups) do
	gstr[#gstr + 1] = g .. "(" .. name_of_group(g) .. ")"
end
unistd.write(1, string.format("uid=%d(%s) gid=%d(%s) groups=%s\n",
	uid, name_of_user(uid), gid, name_of_group(gid), table.concat(gstr, ",")))
