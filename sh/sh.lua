#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local a = arg or { [0] = "sh" }
local src = a[0]:match("(.+/)") or "./"
package.path = src .. "../?.lua;" .. package.path

local unistd = require("posix.unistd")
local fcntl = require("posix.fcntl")
local termio = require("posix.termio")
local dirent = require("posix.dirent")
local stat = require("posix.sys.stat")
local signal = require("posix.signal")
local lexer = require("sh.lexer")
local exec = require("sh.exec")
local env = require("sh.env")
local expand = require("sh.expand")

-- signal state: set by handler, checked by line editor
local sigint_received = false
signal.signal(signal.SIGINT, function()
	sigint_received = true
end)
signal.signal(signal.SIGTSTP, signal.SIG_IGN)

expand.set_sh_path(a[0])
expand.set_run_fn(nil) -- will be set after run_line is defined

-- parse options
local cmd_string = nil
local optind = 0
for opt, optarg, oi in unistd.getopt(a, "c:") do
	if opt == "c" then
		cmd_string = optarg
	end
	optind = oi
end

-- determine $0 and positional params
local script_file = nil
if cmd_string then
	-- with -c: first arg after options is $0, rest are $1..
	local argv = { "sh" }
	if a[optind] then
		argv[1] = a[optind]
		for i = optind + 1, #a do
			argv[#argv + 1] = a[i]
		end
	end
	env.set_argv(argv)
else
	-- first non-option arg is script file
	if a[1] then
		script_file = a[1]
		local argv = { a[1] }
		for i = 2, #a do
			argv[#argv + 1] = a[i]
		end
		env.set_argv(argv)
	else
		env.set_argv({ a[0] or "sh" })
	end
end

local function run_pipeline(pipeline)
	if #pipeline == 0 or (#pipeline == 1 and #pipeline[1] == 0) then
		return tonumber(env.get("?")) or 0
	end
	return exec.execute(pipeline)
end

local function run_chain(chain)
	local status = 0
	for i, entry in ipairs(chain) do
		if i == 1 then
			status = run_pipeline(entry.pipeline)
		else
			local prev_op = chain[i - 1].op
			if prev_op == "&&" then
				if status == 0 then
					status = run_pipeline(entry.pipeline)
				end
			elseif prev_op == "||" then
				if status ~= 0 then
					status = run_pipeline(entry.pipeline)
				end
			else
				status = run_pipeline(entry.pipeline)
			end
		end
	end
	return status
end

local function run_list(list)
	for _, item in ipairs(list) do
		if item.async then
			local pid = unistd.fork()
			if pid == 0 then
				run_chain(item.chain)
				os.exit(tonumber(env.get("?")) or 0)
			end
			env.set_last_bg(pid)
			env.set_status(0)
		else
			local status = run_chain(item.chain)
			env.set_status(status)
		end
	end
end

local compound = require("sh.compound")

local function run_line(line)
	-- get flat tokens to check for compound commands
	local flat = lexer.tokenize_flat(line)
	if not flat then
		unistd.write(2, "sh: parse error\n")
		env.set_status(2)
		return
	end

	-- split flat tokens on ; at top level (respecting if/while/for nesting)
	local segments = {}
	local current = {}
	local depth = 0
	for _, t in ipairs(flat) do
		if t == "if" or t == "while" or t == "until" or t == "for" then
			depth = depth + 1
			current[#current + 1] = t
		elseif t == "fi" or t == "done" then
			depth = depth - 1
			current[#current + 1] = t
		elseif t == ";" and depth == 0 then
			if #current > 0 then
				segments[#segments + 1] = current
			end
			current = {}
		else
			current[#current + 1] = t
		end
	end
	if #current > 0 then
		segments[#segments + 1] = current
	end

	-- execute each segment
	for _, seg in ipairs(segments) do
		if env.get("_break") or env.get("_continue") then
			break
		end
		if compound.is_compound(seg) then
			compound.try_execute(seg)
		else
			-- build list structure directly from flat tokens
			local list = {}
			local chain = {}
			local pipeline = {}
			local current = {}
			for _, t in ipairs(seg) do
				if t == "|" then
					pipeline[#pipeline + 1] = current; current = {}
				elseif t == "&&" or t == "||" then
					pipeline[#pipeline + 1] = current; current = {}
					chain[#chain + 1] = { pipeline = pipeline, op = t }
					pipeline = {}
				elseif t == "&" then
					pipeline[#pipeline + 1] = current; current = {}
					chain[#chain + 1] = { pipeline = pipeline }
					pipeline = {}
					list[#list + 1] = { chain = chain, async = true }
					chain = {}
				else
					current[#current + 1] = t
				end
			end
			pipeline[#pipeline + 1] = current
			chain[#chain + 1] = { pipeline = pipeline }
			list[#list + 1] = { chain = chain, async = false }
			run_list(list)
		end
	end
end

expand.set_run_fn(run_line)
compound.set_run_fn(run_line)

-- -c mode: run command string and exit
if cmd_string then
	run_line(cmd_string)
	os.exit(tonumber(env.get("?")) or 0)
end

-- script file mode: read and execute file
if script_file then
	local fd = fcntl.open(script_file, fcntl.O_RDONLY)
	if not fd then
		unistd.write(2, "sh: " .. script_file .. ": No such file or directory\n")
		os.exit(127)
	end
	local content = ""
	while true do
		local chunk = unistd.read(fd, 8192)
		if not chunk or chunk == "" then
			break
		end
		content = content .. chunk
	end
	unistd.close(fd)
	local pending = ""

	-- check if a string has balanced quotes
	local function quotes_balanced(s)
		local in_single = false
		local in_double = false
		local i = 1
		while i <= #s do
			local c = s:sub(i, i)
			if c == "\\" and not in_single then
				i = i + 1 -- skip escaped char
			elseif c == "'" and not in_double then
				in_single = not in_single
			elseif c == '"' and not in_single then
				in_double = not in_double
			end
			i = i + 1
		end
		return not in_single and not in_double
	end

	for line in content:gmatch("([^\n]*)\n?") do
		if line:sub(-1) == "\\" then
			pending = pending .. line:sub(1, -2)
		else
			pending = pending .. (pending ~= "" and "\n" or "") .. line
			-- check if quotes are balanced
			if not quotes_balanced(pending) then
				-- incomplete, keep accumulating
			else
				-- check if compound command is complete
				local flat = lexer.tokenize_flat(pending)
				if flat then
					local depth = 0
					for _, t in ipairs(flat) do
						if t == "if" or t == "while" or t == "until" or t == "for" then
							depth = depth + 1
						elseif t == "fi" or t == "done" then
							depth = depth - 1
						end
					end
					if depth <= 0 then
						if pending ~= "" then run_line(pending) end
						pending = ""
					end
				else
					if pending ~= "" then run_line(pending) end
					pending = ""
				end
			end
		end
	end
	if pending ~= "" then
		run_line(pending)
	end
	os.exit(tonumber(env.get("?")) or 0)
end

-- interactive/stdin mode
local interactive = unistd.isatty(0) == 1

-- set default PS1 if not already set
if not env.get("PS1") then
	if unistd.getuid() == 0 then
		env.set("PS1", "# ")
	else
		env.set("PS1", "$ ")
	end
end

local function prompt()
	if interactive then
		local ps1 = expand.word(env.get("PS1") or "$ ")
		unistd.write(2, ps1)
	end
end

local function complete_filename(prefix)
	local dir, base
	if prefix:find("/") then
		dir = prefix:match("^(.*/)")
		base = prefix:match("([^/]*)$")
	else
		dir = "."
		base = prefix
	end
	local entries = dirent.dir(dir)
	if not entries then
		return {}
	end
	local matches = {}
	for _, e in ipairs(entries) do
		if e ~= "." and e ~= ".." and e:sub(1, #base) == base then
			local full = (dir == ".") and e or (dir .. e)
			local s = stat.stat(full)
			if s and stat.S_ISDIR(s.st_mode) ~= 0 then
				full = full .. "/"
			end
			matches[#matches + 1] = full
		end
	end
	table.sort(matches)
	return matches
end

local function read_line()
	if not interactive then
		-- non-interactive: simple read
		local buf = {}
		while true do
			local ch = unistd.read(0, 1)
			if not ch or ch == "" then
				if #buf == 0 then
					return nil
				end
				return table.concat(buf)
			end
			if ch == "\n" then
				return table.concat(buf)
			end
			buf[#buf + 1] = ch
		end
	end

	-- interactive: raw mode line editing with tab completion
	local orig = termio.tcgetattr(0)
	local raw = {}
	for k, v in pairs(orig) do
		raw[k] = v
	end
	raw.lflag = raw.lflag & ~(termio.ICANON | termio.ECHO)
	raw.cc = raw.cc or {}
	raw.cc[termio.VMIN] = 1
	raw.cc[termio.VTIME] = 0
	termio.tcsetattr(0, termio.TCSANOW, raw)

	local buf = {}
	local pos = 0 -- cursor position = #buf (end only for simplicity)

	local function redraw()
		-- clear line and rewrite
		unistd.write(2, "\r\027[K")
		prompt()
		unistd.write(2, table.concat(buf))
	end

	while true do
		local ch = unistd.read(0, 1)

		-- check if SIGINT was received
		if sigint_received then
			sigint_received = false
			buf = {}
			unistd.write(2, "\n")
			redraw()
			ch = nil
		end

		if not ch or ch == "" then
			termio.tcsetattr(0, termio.TCSANOW, orig)
			if #buf == 0 then
				return nil
			end
			unistd.write(2, "\n")
			return table.concat(buf)
		end

		local b = ch:byte()

		if ch == "\n" or b == 13 then
			termio.tcsetattr(0, termio.TCSANOW, orig)
			unistd.write(2, "\n")
			return table.concat(buf)
		elseif b == 127 or b == 8 then -- backspace
			if #buf > 0 then
				table.remove(buf)
				redraw()
			end
		elseif b == 9 then -- tab
			-- find current word (last space-delimited token)
			local line = table.concat(buf)
			local prefix = line:match("(%S+)$") or ""
			local matches = complete_filename(prefix)
			if #matches == 1 then
				-- complete it
				local suffix = matches[1]:sub(#prefix + 1)
				for i = 1, #suffix do
					buf[#buf + 1] = suffix:sub(i, i)
				end
				redraw()
			elseif #matches > 1 then
				-- find common prefix
				local common = matches[1]
				for i = 2, #matches do
					local m = matches[i]
					local j = 0
					while j < #common and j < #m and common:sub(j + 1, j + 1) == m:sub(j + 1, j + 1) do
						j = j + 1
					end
					common = common:sub(1, j)
				end
				if #common > #prefix then
					local suffix = common:sub(#prefix + 1)
					for i = 1, #suffix do
						buf[#buf + 1] = suffix:sub(i, i)
					end
					redraw()
				else
					-- show matches
					unistd.write(2, "\n")
					unistd.write(2, table.concat(matches, "  ") .. "\n")
					redraw()
				end
			end
		elseif b == 3 then -- Ctrl-C
			buf = {}
			unistd.write(2, "\n")
			redraw()
		elseif b == 4 then -- Ctrl-D
			termio.tcsetattr(0, termio.TCSANOW, orig)
			if #buf == 0 then
				return nil
			end
		elseif b >= 32 then -- printable
			buf[#buf + 1] = ch
			unistd.write(2, ch)
		end
	end
end

while true do
	prompt()
	local line = read_line()
	if not line then
		break
	end
	-- backslash continuation
	while line:sub(-1) == "\\" do
		line = line:sub(1, -2)
		local cont = read_line()
		if not cont then
			break
		end
		line = line .. cont
	end
	-- accumulate lines for incomplete compound commands
	while true do
		local flat = lexer.tokenize_flat(line)
		if not flat then
			break
		end
		local depth = 0
		for _, t in ipairs(flat) do
			if t == "if" or t == "while" or t == "until" or t == "for" then
				depth = depth + 1
			elseif t == "fi" or t == "done" then
				depth = depth - 1
			end
		end
		if depth <= 0 then
			break
		end
		-- need more input
		if interactive then
			unistd.write(2, "> ")
		end
		local cont = read_line()
		if not cont then
			break
		end
		line = line .. "\n" .. cont
	end
	run_line(line)
	sigint_received = false
end
