#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd   = require("posix.unistd")
local fcntl    = require("posix.fcntl")
local stat     = require("posix.sys.stat")
local notposix = require("luaposixcli.sys")

local scripts = {}
local files = {}
local quiet = false
local inplace, suffix = false, nil

local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "-n" then quiet = true
	elseif a == "-e" then i = i + 1; scripts[#scripts + 1] = arg[i]
	elseif a == "-i" or a:sub(1, 2) == "-i" and #a > 2 then
		-- -i is not POSIX, but every sed people use has it. A suffix
		-- attached to it keeps a copy of the original.
		inplace = true
		if #a > 2 then suffix = a:sub(3) end
	elseif a:sub(1, 1) ~= "-" and #scripts == 0 then
		scripts[#scripts + 1] = a
	else
		files[#files + 1] = a
	end
	i = i + 1
end

if inplace and #files == 0 then
	unistd.write(2, "sed: -i needs a file to edit\n")
	os.exit(2)
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

-- Read the operands as one stream, the way POSIX describes: the files are
-- concatenated, line numbers run on across them, and $ is the last line of
-- the last file. Reading is lazy, so q stops before the later files are
-- opened, and a file that cannot be read is reported without ending the run.
local exit_status = 0

local function line_reader(paths)
	local sources = #paths > 0 and paths or { "-" }
	local idx, fd, buf = 0, nil, ""

	local function open_next()
		while idx < #sources do
			idx = idx + 1
			local path = sources[idx]
			if path == "-" then
				fd = 0
				return true
			end
			local f, err = fcntl.open(path, fcntl.O_RDONLY)
			if f then
				fd = f
				return true
			end
			unistd.write(2, "sed: can't read " .. (err or path .. ": No such file or directory") .. "\n")
			exit_status = 2
		end
		return false
	end

	-- Append the next chunk of input to buf. False once every source is done.
	local function fill()
		while true do
			if not fd and not open_next() then return false end
			local data, err = unistd.read(fd, 8192)
			if data and data ~= "" then
				buf = buf .. data
				return true
			end
			if not data then
				unistd.write(2, "sed: read error on " .. sources[idx] .. ": " .. (err or "read failed") .. "\n")
				exit_status = 2
			end
			if fd ~= 0 then unistd.close(fd) end
			fd = nil
		end
	end

	return function()
		while true do
			local nl = buf:find("\n", 1, true)
			if nl then
				local line = buf:sub(1, nl - 1)
				buf = buf:sub(nl + 1)
				return line
			end
			if not fill() then
				if buf ~= "" then
					local line = buf
					buf = ""
					return line
				end
				return nil
			end
		end
	end
end

-- One line of lookahead, so the $ address knows the last line without
-- holding the whole input in memory.
local function stream(paths)
	local next_line = line_reader(paths)
	local pending = next_line()
	return function()
		local line = pending
		if line == nil then return nil end
		pending = next_line()
		return line, (pending == nil)
	end
end

-- Run the script over one stream, handing each surviving line to emit.
-- Returns true if the script quit.
local function run(read_line, emit)
	local in_range = {}
	local lineno = 0

	while true do
		local raw, last = read_line()
		if raw == nil then return false end
		local line = raw
		lineno = lineno + 1
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
				elseif c.cmd == "p" then
					print_extra = true
				elseif c.cmd == "q" then
					if not quiet then emit(line .. "\n") end
					return true
				elseif c.cmd == "s" then
					local new, changed = do_sub(line, c.pattern, c.replacement, c.global)
					line = new
					if changed and c.print then print_extra = true end
				end
			end
		end

		if not deleted then
			if not quiet then emit(line .. "\n") end
			if print_extra then emit(line .. "\n") end
		end
	end
end

if not inplace then
	run(stream(files), function(text) unistd.write(1, text) end)
	os.exit(exit_status)
end

-- -i edits each file on its own, so line numbers and $ are per file, and
-- the result goes through a temporary in the same directory.
for _, path in ipairs(files) do
	local st = stat.stat(path)
	if not st then
		unistd.write(2, "sed: can't read " .. path .. ": No such file or directory\n")
		exit_status = 2
	else
		local tmp = path .. ".sed" .. unistd.getpid()
		local out, oerr = io.open(tmp, "wb")
		if not out then
			unistd.write(2, "sed: " .. (oerr or (tmp .. ": cannot write")) .. "\n")
			exit_status = 2
		else
			local quit = run(stream({ path }), function(text) out:write(text) end)
			out:close()
			if suffix and suffix ~= "" then
				os.rename(path, path .. suffix)
			end
			local ok, rerr = os.rename(tmp, path)
			if not ok then
				unistd.write(2, "sed: " .. (rerr or (path .. ": cannot replace")) .. "\n")
				os.remove(tmp)
				exit_status = 2
			else
				stat.chmod(path, st.st_mode & tonumber("7777", 8))
			end
			if quit then break end
		end
	end
end

os.exit(exit_status)
