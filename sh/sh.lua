#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local a = arg or { [0] = "sh" }
local src = a[0]:match("(.+/)") or "./"
local prefix = src .. "../"
package.path = prefix .. "?.lua;" .. prefix .. "share/lua/5.4/?.lua;" .. package.path


local unistd = require("posix.unistd")
local fcntl = require("posix.fcntl")
local ok_termio, termio = pcall(require, "posix.termio")
local dirent = require("posix.dirent")
local stat = require("posix.sys.stat")
local signal = require("posix.signal")
local lexer = require("sh.lexer")
local walk_mod = require("sh.walk")
local env = require("sh.env")
local expand = require("sh.expand")

-- Disable buffering on stdout/stderr so output appears immediately
io.stdout:setvbuf("no")
io.stderr:setvbuf("no")

-- signal state: set by handler, checked by line editor
local sigint_received = false
signal.signal(signal.SIGINT, function()
	sigint_received = true
end)
signal.signal(signal.SIGTSTP, signal.SIG_IGN)
signal.signal(signal.SIGPIPE, signal.SIG_IGN)

expand.set_sh_path(a[0])
expand.set_run_fn(nil) -- will be set after run_line is defined

-- parse options
local cmd_string = nil
local login = (a[0] or ""):sub(1, 1) == "-"
local optind = 1
for opt, optarg, oi in unistd.getopt(a, "c:l") do
	if opt == "c" then
		cmd_string = optarg
	elseif opt == "l" then
		login = true
	end
	optind = oi
end
if a[optind] == "--" then optind = optind + 1 end

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
	if a[optind] then
		script_file = a[optind]
		local argv = { a[optind] }
		for i = optind + 1, #a do
			argv[#argv + 1] = a[i]
		end
		env.set_argv(argv)
	else
		env.set_argv({ a[0] or "sh" })
	end
end

local compound = require("sh.compound")
local parse = require("sh.parse")
local walker = require("sh.walk")

local function run_line(line, heredoc_bodies)
	local flat = lexer.tokenize_flat(line)
	if not flat then
		unistd.write(2, "sh: parse error\n")
		env.set_status(2)
		return
	end
	local ast, err = parse.parse(flat)
	if not ast then
		if err == "incomplete" then
			unistd.write(2, "sh: syntax error: unexpected end of input\n")
		end
		return
	end
	-- Attach here-doc bodies, in the order the delimiters were written
	if heredoc_bodies then
		local next_body = 1
		local function attach_heredocs(node)
			if not node then return end
			if node.type == "simple" and node.heredocs and #node.heredocs > 0 then
				node.heredoc_bodies = {}
				for _, hd in ipairs(node.heredocs) do
					node.heredoc_bodies[#node.heredoc_bodies + 1] = {
						text = heredoc_bodies[next_body] or "",
						quoted = hd.quoted,
					}
					next_body = next_body + 1
				end
			end
			-- Recurse into child nodes
			if node.items then for _, item in ipairs(node.items) do attach_heredocs(item) end end
			if node.cmds then for _, cmd in ipairs(node.cmds) do attach_heredocs(cmd) end end
			if node.left then attach_heredocs(node.left) end
			if node.right then attach_heredocs(node.right) end
			if node.body then attach_heredocs(node.body) end
			if node.cond then attach_heredocs(node.cond) end
			if node.then_body then attach_heredocs(node.then_body) end
			if node.else_body then attach_heredocs(node.else_body) end
		end
		attach_heredocs(ast)
	end
	local status = walker.walk(ast)
	env.set_status(status or 0)
end

expand.set_run_fn(run_line)

local interactive = unistd.isatty(0) == 1
env.set_interactive(interactive)

-- A login shell reads the profiles; any interactive shell reads $ENV.
-- A file that is not there is not an error.
local function source_if_readable(path)
	if path and path ~= "" and unistd.access(path, "r") == 0 then
		run_line(". '" .. path .. "'")
	end
end

-- One text, whether it came from -c, a script or a dot file. The
-- here-document bodies are the lines after the command, so the text
-- has to be read as lines rather than handed to the parser whole.
-- A quote left open at the end of a line is a line that is not finished,
-- wherever it came from.
local function quotes_balanced(s)
	local i = 1
	while i <= #s do
		local c = s:sub(i, i)
		if c == "\\" then
			i = i + 2
		elseif c == "'" then
			local j = s:find("'", i + 1, true)
			if not j then return false end
			i = j + 1
		elseif c == '"' then
			local e = lexer.skip_dquote(s, i + 1)
			if not e then return false end
			i = e
		elseif c == "$" and s:sub(i + 1, i + 1) == "(" then
			local e = lexer.skip_cmdsub(s, i + 1)
			if not e then return false end
			i = e
		else
			i = i + 1
		end
	end
	return true
end

local function run_text(content)
local pending = ""

-- Split content into lines for indexed access. Blank lines are kept:
-- a here-document body may contain them.
local lines = {}
do
	local text = content
	if text:sub(-1) ~= "\n" then text = text .. "\n" end
	for l in text:gmatch("([^\n]*)\n") do lines[#lines + 1] = l end
end

-- Extract here-doc delimiters from a flat token list
local function get_heredoc_delims(flat)
	local delims = {}
	for i = 1, #flat do
		if (flat[i] == "<<" or flat[i] == "<<-") and flat[i + 1] then
			local strip = (flat[i] == "<<-")
			local delim = flat[i + 1]
			-- A quoted delimiter means the body is literal
			local quoted = false
			if delim:sub(1, 1) == "'" or delim:sub(1, 1) == '"' then
				quoted = true
				delim = delim:sub(2, -2)
			end
			delims[#delims + 1] = { delim = delim, strip = strip, quoted = quoted }
		end
	end
	return delims
end

-- A body starts on the line after the one that names it, whether or
-- not the command is finished: the lines inside a loop belong to the
-- here-document, not to the loop.
local function takebody(lines, li, hd)
	local body = {}
	while li <= #lines do
		local hl = lines[li]
		li = li + 1
		if hd.strip then hl = hl:gsub("^\t+", "") end
		if hl == hd.delim then break end
		body[#body + 1] = hl .. "\n"
	end
	return table.concat(body), li
end

local li = 1
local bodies = {}
while li <= #lines do
	local line = lines[li]
	li = li + 1
	if line:sub(-1) == "\\" then
		pending = pending .. line:sub(1, -2)
	else
		pending = pending .. (pending ~= "" and "\n" or "") .. line
		if quotes_balanced(pending) then
			local this = lexer.tokenize_flat(line)
			for _, hd in ipairs(this and get_heredoc_delims(this) or {}) do
				local body
				body, li = takebody(lines, li, hd)
				bodies[#bodies + 1] = body
			end
			local flat = lexer.tokenize_flat(pending)
			if (flat and parse.is_complete(flat)) or not flat then
				if pending ~= "" then
					run_line(pending, #bodies > 0 and bodies or nil)
				end
				pending, bodies = "", {}
			end
		end
	end
end
if pending ~= "" then
	run_line(pending, #bodies > 0 and bodies or nil)
end
end

expand.set_text_fn(run_text)

if login then
	source_if_readable("/etc/profile")
	local home = env.get("HOME")
	if home and home ~= "" then source_if_readable(home .. "/.profile") end
end
if interactive then
	local envfile = env.get("ENV")
	if envfile then source_if_readable(expand.word(envfile)) end
end


-- -c mode: run command string and exit
if cmd_string then
	run_text(cmd_string)
	env.run_exit_trap()
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
	run_text(content)
	env.run_exit_trap()
	os.exit(tonumber(env.get("?")) or 0)
end

-- interactive/stdin mode
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
	local ok, entries = pcall(dirent.dir, dir)
	if not ok or not entries then
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

local history = {}
local history_pos = 1

-- literal: the caller wants the line as typed, with no completion. A
-- here-document body and a continuation line are text, not commands.
local function read_line(literal)
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
	local orig = ok_termio and termio.tcgetattr(0) or nil
	if not orig then
		-- tcgetattr failed - fall back to simple line read
		-- Print prompt since the main loop's prompt() already ran,
		-- but if we got here the terminal might need a nudge
		local buf = {}
		while true do
			local ch = unistd.read(0, 1)
			if not ch or ch == "" then
				if #buf == 0 then return nil end
				return table.concat(buf)
			end
			if ch == "\n" then return table.concat(buf) end
			buf[#buf + 1] = ch
		end
	end
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
			goto continue
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
		elseif b == 9 and literal then -- tab as text
			buf[#buf + 1] = "\t"
			redraw()
		elseif b == 9 then -- tab
			-- find current word (last space-delimited token)
			local line = table.concat(buf)
			local prefix = line:match("(%S+)$") or ""
			-- Use command completion if on first word (and not an absolute/relative path)
			local matches
			local before_prefix = line:sub(1, #line - #prefix)
			if not before_prefix:find("%S") and not prefix:match("^[./]") then
				-- First word: complete from PATH + builtins
				matches = {}
				local seen = {}
				-- builtins
				local builtins = walk_mod.get_builtins()
				for name in pairs(builtins) do
					if name:sub(1, #prefix) == prefix and not seen[name] then
						matches[#matches + 1] = name
						seen[name] = true
					end
				end
				-- PATH
				local path = env.get("PATH") or "/bin:/usr/bin"
				for dir in path:gmatch("[^:]+") do
					-- a PATH entry that is not there is not an error
					local ok, entries = pcall(dirent.dir, dir)
					if ok and entries then
						for _, e in ipairs(entries) do
							if e:sub(1, #prefix) == prefix and not seen[e] then
								local full = dir .. "/" .. e
								if unistd.access(full, "x") == 0 then
									matches[#matches + 1] = e
									seen[e] = true
								end
							end
						end
					end
				end
				table.sort(matches)
			else
				matches = complete_filename(prefix)
			end
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
		elseif b == 21 then -- Ctrl-U: clear line
			buf = {}
			redraw()
		elseif b == 23 then -- Ctrl-W: delete last word
			while #buf > 0 and buf[#buf] == " " do table.remove(buf) end
			while #buf > 0 and buf[#buf] ~= " " do table.remove(buf) end
			redraw()
		elseif b == 1 then -- Ctrl-A: (no cursor movement yet, just beep)
		elseif b == 5 then -- Ctrl-E: (no cursor movement yet)
		elseif b == 11 then -- Ctrl-K: kill to end (no-op without cursor pos)
		elseif b == 12 then -- Ctrl-L: clear screen, redraw
			unistd.write(2, "\027[2J\027[H")
			redraw()
		elseif b == 27 then -- Escape sequence (arrows)
			local c2 = unistd.read(0, 1)
			if c2 == "[" then
				local c3 = unistd.read(0, 1)
				if c3 == "A" then -- Up arrow: previous history
					if history_pos > 1 then
						history_pos = history_pos - 1
						buf = {}
						for i = 1, #history[history_pos] do
							buf[i] = history[history_pos]:sub(i, i)
						end
						redraw()
					end
				elseif c3 == "B" then -- Down arrow: next history
					if history_pos < #history then
						history_pos = history_pos + 1
						buf = {}
						for i = 1, #history[history_pos] do
							buf[i] = history[history_pos]:sub(i, i)
						end
						redraw()
					elseif history_pos == #history then
						history_pos = #history + 1
						buf = {}
						redraw()
					end
				-- C (right) and D (left) ignored for now (no cursor pos)
				end
			end
		elseif b >= 32 then -- printable
			buf[#buf + 1] = ch
			unistd.write(2, ch)
		end
		::continue::
	end
end


while true do
	prompt()
	history_pos = #history + 1
	local line = read_line()
	if not line then
		break
	end
	-- Add to history (skip empty and duplicates)
	if line ~= "" and line ~= history[#history] then
		history[#history + 1] = line
	end
	history_pos = #history + 1
	-- backslash continuation
	while line:sub(-1) == "\\" do
		line = line:sub(1, -2)
		local cont = read_line(true)
		if not cont then
			break
		end
		line = line .. cont
	end
	-- A here-document body is read as soon as the line naming it is in,
	-- because the lines that follow belong to the body and not to the
	-- compound command still being typed.
	local heredoc_bodies
	local function takebodies(text)
		local flat = lexer.tokenize_flat(text)
		if not flat then return end
		for i = 1, #flat do
			if (flat[i] == "<<" or flat[i] == "<<-") and flat[i + 1] then
				local strip = (flat[i] == "<<-")
				local delim = flat[i + 1]
				if delim:sub(1, 1) == "'" or delim:sub(1, 1) == '"' then
					delim = delim:sub(2, -2)
				end
				local body = {}
				while true do
					local hl = read_line(true)
					if not hl then break end
					if strip then hl = hl:gsub("^\t+", "") end
					if hl == delim then break end
					body[#body + 1] = hl .. "\n"
				end
				heredoc_bodies = heredoc_bodies or {}
				heredoc_bodies[#heredoc_bodies + 1] = table.concat(body)
			end
		end
	end

	local function readclosed(text)
		while text and not quotes_balanced(text) do
			if interactive then
				unistd.write(2, "> ")
			end
			local more = read_line(true)
			if not more then break end
			text = text .. "\n" .. more
		end
		return text
	end

	line = readclosed(line)
	takebodies(line)
	-- accumulate lines for incomplete compound commands
	while true do
		local flat = lexer.tokenize_flat(line)
		if not flat then
			break
		end
		if parse.is_complete(flat) then
			break
		end
		-- need more input
		if interactive then
			unistd.write(2, "> ")
		end
		local cont = readclosed(read_line(true))
		if not cont then
			break
		end
		line = line .. "\n" .. cont
		takebodies(cont)
	end
	run_line(line, heredoc_bodies)
	sigint_received = false
end
