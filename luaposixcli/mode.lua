-- SPDX-License-Identifier: ISC
-- luaposixcli/mode.lua - the symbolic mode grammar chmod, mkdir and
-- install all take: [ugoa]*[-+=][rwxXst]* in a comma separated list.
local stat = require("posix.sys.stat")

local M = {}

local SETUID = tonumber("4000", 8)
local SETGID = tonumber("2000", 8)
local STICKY = tonumber("1000", 8)
local ALLBITS = tonumber("7777", 8)
local ANY_EXEC = tonumber("111", 8)

local shift = { u = 6, g = 3, o = 0 }
local special = { u = SETUID, g = SETGID }

local function current_umask()
	local mask = stat.umask(0)
	stat.umask(mask)
	return mask
end

-- Apply one symbolic mode expression to mode. isdir selects the X behavior.
local function apply_symbolic(spec, mode, isdir)
	local mask = current_umask()
	for clause in (spec .. ","):gmatch("([^,]*),") do
		local pos = 1
		local who = clause:match("^([ugoa]*)", pos)
		pos = pos + #who
		local classes = {}
		local use_umask = false
		if who == "" then
			classes, use_umask = { "u", "g", "o" }, true
		else
			local seen = {}
			for c in who:gmatch(".") do
				if c == "a" then
					for _, k in ipairs({ "u", "g", "o" }) do seen[k] = true end
				else
					seen[c] = true
				end
			end
			for _, k in ipairs({ "u", "g", "o" }) do
				if seen[k] then classes[#classes + 1] = k end
			end
		end
		if pos > #clause then error("invalid mode: " .. spec, 0) end
		while pos <= #clause do
			local op = clause:sub(pos, pos)
			if not op:match("[-+=]") then error("invalid mode: " .. spec, 0) end
			pos = pos + 1
			local copy = clause:match("^([ugo])", pos)
			local perms = ""
			if copy then
				pos = pos + 1
			else
				perms = clause:match("^([rwxXst]*)", pos)
				pos = pos + #perms
			end
			if pos <= #clause and not clause:sub(pos, pos):match("[-+=]") then
				error("invalid mode: " .. spec, 0)
			end

			local bits = 0
			if copy then
				local src = (mode >> shift[copy]) & 7
				for _, k in ipairs(classes) do bits = bits | (src << shift[k]) end
			else
				local base = 0
				if perms:find("r", 1, true) then base = base | 4 end
				if perms:find("w", 1, true) then base = base | 2 end
				if perms:find("x", 1, true) then base = base | 1 end
				if perms:find("X", 1, true) and (isdir or (mode & ANY_EXEC) ~= 0) then
					base = base | 1
				end
				for _, k in ipairs(classes) do
					bits = bits | (base << shift[k])
					if perms:find("s", 1, true) and special[k] then
						bits = bits | special[k]
					end
				end
				if perms:find("t", 1, true) then bits = bits | STICKY end
			end
			if use_umask then bits = bits & ~mask end

			if op == "+" then
				mode = mode | bits
			elseif op == "-" then
				mode = mode & ~bits
			else
				local clear = 0
				for _, k in ipairs(classes) do
					clear = clear | (7 << shift[k])
					if special[k] then clear = clear | special[k] end
					if k == "o" then clear = clear | STICKY end
				end
				mode = (mode & ~clear) | bits
			end
		end
	end
	return mode & ALLBITS
end


-- A mode written either way. current is what the file has now, which an
-- expression like go-w needs; isdir picks the X behavior.
function M.parse(spec, current, isdir)
	local octal = spec:match("^[0-7]+$") and tonumber(spec, 8)
	if octal then return octal end
	if not spec:match("^[ugoa]*[-+=]") then
		return nil, "invalid mode: " .. spec
	end
	local ok, result = pcall(apply_symbolic, spec, current or 0, isdir)
	if not ok then return nil, tostring(result) end
	return result
end

return M
