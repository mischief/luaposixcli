#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd   = require("posix.unistd")
local fcntl    = require("posix.fcntl")
local notposix = require("luaposixcli.sys")

local scripts = {}
local files = {}
local quiet = false

local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "-n" then quiet = true
	elseif a == "-e" then i = i + 1; scripts[#scripts + 1] = arg[i]
	elseif a:sub(1, 1) ~= "-" and #scripts == 0 then
		scripts[#scripts + 1] = a
	else
		files[#files + 1] = a
	end
	i = i + 1
end

-- parse a sed command: [addr[,addr]]command[args]
local function parse_commands(script)
	local cmds = {}
	for stmt in script:gmatch("[^\n;]+") do
		local addr1, addr2, cmd, rest
		local s = stmt:match("^%s*(.-)%s*$")

		-- parse address(es)
		local function parse_addr(str)
			if str:match("^%d+") then
				local n, r = str:match("^(%d+)(.*)")
				return tonumber(n), r
			elseif str:sub(1, 1) == "$" then
				return "$", str:sub(2)
			elseif str:sub(1, 1) == "/" then
				local pat, r = str:match("^/([^/]*)/?(.*)")
				return { regex = pat }, r
			end
			return nil, str
		end

		addr1, s = parse_addr(s)
		if addr1 and s:sub(1, 1) == "," then
			addr2, s = parse_addr(s:sub(2))
		end

		cmd = s:sub(1, 1)
		rest = s:sub(2)

		if cmd == "s" then
			local delim = rest:sub(1, 1)
			-- parse s/pat/repl/flags
			local pat, repl, flags = rest:match("^.(.-)" .. delim .. "(.-)" .. delim .. "(.*)$")
			if not pat then
				pat, repl = rest:match("^.(.-)" .. delim .. "(.*)$")
				flags = ""
			end
			cmds[#cmds + 1] = {
				addr1 = addr1, addr2 = addr2, cmd = "s",
				pattern = pat, replacement = repl,
				global = flags and flags:find("g") ~= nil,
				print = flags and flags:find("p") ~= nil,
			}
		else
			cmds[#cmds + 1] = { addr1 = addr1, addr2 = addr2, cmd = cmd, rest = rest }
		end
	end
	return cmds
end

local commands = {}
for _, s in ipairs(scripts) do
	local c = parse_commands(s)
	for _, cmd in ipairs(c) do commands[#commands + 1] = cmd end
end

-- check if address matches
local function addr_match(addr, lineno, line, last)
	if addr == nil then return true end
	if type(addr) == "number" then return lineno == addr end
	if addr == "$" then return last end
	if type(addr) == "table" and addr.regex then
		return notposix.regmatch(addr.regex, line, 0)
	end
	return false
end

-- perform substitution using regcomp/regexec
local function do_sub(line, pattern, replacement, global)
	local re = notposix.regcomp(pattern, 0)
	if not re then return line, false end

	local changed = false
	local result = ""
	local remaining = line

	repeat
		local m = re:exec(remaining)
		if not m or not m[1] then break end
		changed = true
		local so, eo = m[1][1], m[1][2]
		-- build replacement with \1-\9 backreferences
		local repl = replacement:gsub("\\(%d)", function(n)
			local idx = tonumber(n) + 1
			if m[idx] then return remaining:sub(m[idx][1], m[idx][2]) end
			return ""
		end)
		repl = repl:gsub("&", remaining:sub(so, eo))
		result = result .. remaining:sub(1, so - 1) .. repl
		remaining = remaining:sub(eo + 1)
	until not global

	return result .. remaining, changed
end

-- read input
local content = ""
if #files == 0 then
	while true do
		local data = unistd.read(0, 8192)
		if not data or data == "" then break end
		content = content .. data
	end
else
	for _, f in ipairs(files) do
		local fd = fcntl.open(f, fcntl.O_RDONLY)
		if not fd then
			unistd.write(2, "sed: " .. f .. ": No such file or directory\n")
			os.exit(1)
		end
		while true do
			local data = unistd.read(fd, 8192)
			if not data or data == "" then break end
			content = content .. data
		end
		unistd.close(fd)
	end
end

-- split into lines
local lines = {}
for line in content:gmatch("([^\n]*)\n?") do
	lines[#lines + 1] = line
end
if #lines > 0 and lines[#lines] == "" then table.remove(lines) end

-- execute
local in_range = {}
for lineno, line in ipairs(lines) do
	local last = (lineno == #lines)
	local output = true
	local print_extra = false
	local deleted = false

	for ci, c in ipairs(commands) do
		-- check address
		local match
		if c.addr1 == nil then
			match = true
		elseif c.addr2 == nil then
			match = addr_match(c.addr1, lineno, line, last)
		else
			-- range
			if in_range[ci] then
				match = true
				if addr_match(c.addr2, lineno, line, last) then
					in_range[ci] = false
				end
			elseif addr_match(c.addr1, lineno, line, last) then
				match = true
				in_range[ci] = true
			else
				match = false
			end
		end

		if match and not deleted then
			if c.cmd == "d" then
				deleted = true
				output = false
			elseif c.cmd == "p" then
				print_extra = true
			elseif c.cmd == "q" then
				if not quiet then unistd.write(1, line .. "\n") end
				os.exit(0)
			elseif c.cmd == "s" then
				local new, changed = do_sub(line, c.pattern, c.replacement, c.global)
				line = new
				if changed and c.print then print_extra = true end
			end
		end
	end

	if not deleted then
		if not quiet then unistd.write(1, line .. "\n") end
		if print_extra then unistd.write(1, line .. "\n") end
	end
end
