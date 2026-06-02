-- SPDX-License-Identifier: ISC
-- sh/exec.lua: execute a pipeline of commands
local unistd = require("posix.unistd")
local wait = require("posix.sys.wait")
local stdlib = require("posix.stdlib")
local fcntl = require("posix.fcntl")
local env = require("sh.env")
local expand = require("sh.expand")

local redir_ops = { [">"] = true, [">>"] = true, ["<"] = true, [">&"] = true, ["<&"] = true }

-- parse redirections from args, return cleaned args + redirections list
-- each redir: { fd = N, op = ">"|">>"|"<"|">&"|"<&", target = "file" }
local function parse_redirections(args)
	local clean = {}
	local redirs = {}
	local i = 1
	while i <= #args do
		local fd, op, target
		-- check for "N>" pattern: previous token is a digit, current is operator
		if redir_ops[args[i]] then
			-- check if previous clean token is a bare fd number
			if #clean > 0 and clean[#clean]:match("^%d+$") and #clean[#clean] <= 2 then
				fd = tonumber(table.remove(clean))
			end
			op = args[i]
			target = args[i + 1]
			i = i + 2
			if not fd then
				if op == "<" or op == "<&" then
					fd = 0
				else
					fd = 1
				end
			end
			redirs[#redirs + 1] = { fd = fd, op = op, target = target }
		else
			clean[#clean + 1] = args[i]
			i = i + 1
		end
	end
	return clean, redirs
end

-- apply redirections (in child process or for builtins)
-- returns list of saved fds for restore, or nil on error
local function apply_redirections(redirs)
	local saved = {}
	for _, r in ipairs(redirs) do
		if r.op == ">" then
			local fd = fcntl.open(r.target, fcntl.O_WRONLY + fcntl.O_CREAT + fcntl.O_TRUNC, 438)
			if not fd then
				return nil
			end
			saved[#saved + 1] = { fd = r.fd, saved = unistd.dup(r.fd) }
			unistd.dup2(fd, r.fd)
			unistd.close(fd)
		elseif r.op == ">>" then
			local fd = fcntl.open(r.target, fcntl.O_WRONLY + fcntl.O_CREAT + fcntl.O_APPEND, 438)
			if not fd then
				return nil
			end
			saved[#saved + 1] = { fd = r.fd, saved = unistd.dup(r.fd) }
			unistd.dup2(fd, r.fd)
			unistd.close(fd)
		elseif r.op == "<" then
			local fd = fcntl.open(r.target, fcntl.O_RDONLY)
			if not fd then
				return nil
			end
			saved[#saved + 1] = { fd = r.fd, saved = unistd.dup(r.fd) }
			unistd.dup2(fd, r.fd)
			unistd.close(fd)
		elseif r.op == ">&" then
			if r.target == "-" then
				unistd.close(r.fd)
			else
				local src = tonumber(r.target)
				if src then
					saved[#saved + 1] = { fd = r.fd, saved = unistd.dup(r.fd) }
					unistd.dup2(src, r.fd)
				end
			end
		elseif r.op == "<&" then
			if r.target == "-" then
				unistd.close(r.fd)
			else
				local src = tonumber(r.target)
				if src then
					saved[#saved + 1] = { fd = r.fd, saved = unistd.dup(r.fd) }
					unistd.dup2(src, r.fd)
				end
			end
		end
	end
	return saved
end

local function restore_redirections(saved)
	for i = #saved, 1, -1 do
		unistd.dup2(saved[i].saved, saved[i].fd)
		unistd.close(saved[i].saved)
	end
end

local function find_in_path(cmd)
	if cmd:find("/") then
		return cmd
	end
	local path = env.get("PATH") or "/bin:/usr/bin"
	for dir in path:gmatch("[^:]+") do
		local full = dir .. "/" .. cmd
		if unistd.access(full, "x") == 0 then
			return full
		end
	end
	return nil
end

-- built-in: export [NAME[=VALUE] ...]
local function builtin_export(args)
	for i = 2, #args do
		if expand.is_assignment(args[i]) then
			local name, val = expand.parse_assignment(args[i])
			env.set(name, expand.word(val))
			env.export(name)
		else
			env.export(args[i])
		end
	end
	return 0
end

-- built-in: unset NAME ...
local function builtin_unset(args)
	for i = 2, #args do
		env.unset(args[i])
	end
	return 0
end

-- built-in: set [-+][flags]
local function builtin_set(args)
	for i = 2, #args do
		local a = args[i]
		local mode = a:sub(1, 1)
		if mode == "-" or mode == "+" then
			for j = 2, #a do
				env.set_opt(a:sub(j, j), mode == "-")
			end
		end
	end
	return 0
end

-- trace: write expanded command to stderr if set -x is active
local function trace(args)
	if not env.get_opt("x") then
		return
	end
	local ps4 = env.get("PS4") or "+ "
	unistd.write(2, ps4 .. table.concat(args, " ") .. "\n")
end

local builtins = {
	export = builtin_export,
	unset = builtin_unset,
	set = builtin_set,
	[":"] = function()
		return 0
	end,
	["trap"] = function(args)
		local signal_mod = require("posix.signal")
		local traps = env.get_traps and env.get_traps() or nil
		if not traps then return 0 end
		if #args == 1 then
			-- List traps
			for sig, action in pairs(traps) do
				unistd.write(1, "trap -- '" .. action .. "' " .. sig .. "\n")
			end
			return 0
		end
		local action = args[2]
		local sig_names = {}
		for i = 3, #args do sig_names[#sig_names + 1] = args[i] end
		if #sig_names == 0 then
			-- trap '' means list, trap 'cmd' with no signals is error
			sig_names[1] = "EXIT"
		end
		for _, sig in ipairs(sig_names) do
			if action == "" or action == "-" then
				-- Reset to default
				traps[sig] = nil
				if sig ~= "EXIT" and sig ~= "0" then
					local signo = signal_mod["SIG" .. sig]
					if signo then signal_mod.signal(signo, signal_mod.SIG_DFL) end
				end
			else
				traps[sig] = action
				if sig ~= "EXIT" and sig ~= "0" then
					local signo = signal_mod["SIG" .. sig]
					if signo then
						signal_mod.signal(signo, function()
							local run_fn = require("sh.expand").get_run_fn()
							if run_fn then run_fn(action) end
						end)
					end
				end
			end
		end
		return 0
	end,
	["return"] = function(args)
		local n = tonumber(args[2]) or tonumber(env.get("?")) or 0
		env.set("_return", tostring(n))
		return n
	end,
	["eval"] = function(args)
		local s = table.concat(args, " ", 2)
		if s ~= "" then
			local run_fn = require("sh.expand").get_run_fn and require("sh.expand").get_run_fn()
			if run_fn then run_fn(s) end
		end
		return tonumber(env.get("?")) or 0
	end,
	["shift"] = function(args)
		local n = tonumber(args[2]) or 1
		local argv = env.get_argv()
		if n >= #argv then
			env.set_argv({ argv[1] })
		else
			local new = { argv[1] }
			for i = n + 2, #argv do new[#new + 1] = argv[i] end
			env.set_argv(new)
		end
		return 0
	end,
	["."] = function(args)
		if not args[2] then
			unistd.write(2, "sh: .: filename argument required\n")
			return 2
		end
		local path = args[2]
		if not path:find("/") then
			-- Search PATH
			local p = env.get("PATH") or "/bin:/usr/bin"
			local found
			for dir in p:gmatch("[^:]+") do
				local full = dir .. "/" .. path
				if unistd.access(full, "r") == 0 then found = full; break end
			end
			if not found and unistd.access(path, "r") == 0 then found = path end
			path = found
		end
		if not path then
			unistd.write(2, "sh: .: " .. args[2] .. ": not found\n")
			return 1
		end
		local fd = fcntl.open(path, fcntl.O_RDONLY)
		if not fd then
			unistd.write(2, "sh: .: " .. args[2] .. ": No such file or directory\n")
			return 1
		end
		local chunks = {}
		while true do
			local data = unistd.read(fd, 8192)
			if not data or data == "" then break end
			chunks[#chunks + 1] = data
		end
		unistd.close(fd)
		local content = table.concat(chunks)
		local run_fn = require("sh.expand").get_run_fn and require("sh.expand").get_run_fn()
		if run_fn then
			for line in content:gmatch("([^\n]+)") do
				run_fn(line)
			end
		end
		return tonumber(env.get("?")) or 0
	end,
	["command"] = function(args)
		-- command [-v|-V] cmd [args...]
		if #args < 2 then return 0 end
		local mode = nil
		local start = 2
		if args[2] == "-v" then mode = "v"; start = 3
		elseif args[2] == "-V" then mode = "V"; start = 3
		end
		if mode then
			if not args[start] then return 1 end
			local name = args[start]
			-- Check builtins
			if builtins[name] then
				if mode == "v" then unistd.write(1, name .. "\n")
				else unistd.write(1, name .. " is a shell builtin\n") end
				return 0
			end
			-- Check PATH
			local p = env.get("PATH") or "/bin:/usr/bin"
			for dir in p:gmatch("[^:]+") do
				local full = dir .. "/" .. name
				if unistd.access(full, "x") == 0 then
					if mode == "v" then unistd.write(1, full .. "\n")
					else unistd.write(1, name .. " is " .. full .. "\n") end
					return 0
				end
			end
			return 1
		end
		-- command cmd [args...]: skip functions, run builtin or external
		local cmd_args = {}
		for i = start, #args do cmd_args[#cmd_args + 1] = args[i] end
		-- Check builtins (skip functions)
		if builtins[cmd_args[1]] then
			return builtins[cmd_args[1]](cmd_args)
		end
		-- External
		local path
		if cmd_args[1]:find("/") then
			path = cmd_args[1]
		else
			local p = env.get("PATH") or "/bin:/usr/bin"
			for dir in p:gmatch("[^:]+") do
				local full = dir .. "/" .. cmd_args[1]
				if unistd.access(full, "x") == 0 then path = full; break end
			end
		end
		if not path then
			unistd.write(2, "sh: " .. cmd_args[1] .. ": command not found\n")
			return 127
		end
		local pid = unistd.fork()
		if pid == 0 then
			local rest = {}
			for i = 2, #cmd_args do rest[#rest + 1] = cmd_args[i] end
			unistd.execp(path, rest)
			os.exit(127)
		end
		local _, reason, status = wait.wait(pid)
		if reason == "exited" then return status end
		if reason == "killed" then return 128 + status end
		return 1
	end,
	["type"] = nil, -- defined below (needs builtins reference)
	["break"] = function(args)
		env.set("_break", tostring(tonumber(args[2]) or 1))
		return 0
	end,
	["continue"] = function(args)
		env.set("_continue", tostring(tonumber(args[2]) or 1))
		return 0
	end,
	test = require("sh.test").builtin,
	["["] = require("sh.test").builtin,
	["true"] = function()
		return 0
	end,
	["false"] = function()
		return 1
	end,
	echo = function(args)
		local out = table.concat(args, " ", 2) .. "\n"
		unistd.write(1, out)
		return 0
	end,
	getopts = function(args)
		-- getopts optstring name [arg...]
		if #args < 3 then return 2 end
		local optstring = args[2]
		local varname = args[3]
		-- Get positional params or explicit args
		local params
		if args[4] then
			params = {}
			for i = 4, #args do params[#params + 1] = args[i] end
		else
			-- Use shell positional parameters ($1, $2, ...)
			local all = env.get("@")
			params = {}
			for w in all:gmatch("%S+") do params[#params + 1] = w end
		end
		local optind = tonumber(env.get("OPTIND")) or 1
		if optind > #params then
			env.set(varname, "?")
			return 1
		end
		local arg_val = params[optind]
		if not arg_val or arg_val:sub(1, 1) ~= "-" or arg_val == "-" then
			env.set(varname, "?")
			return 1
		end
		if arg_val == "--" then
			env.set("OPTIND", tostring(optind + 1))
			env.set(varname, "?")
			return 1
		end
		-- Get current char position within the arg (for bundled opts like -abc)
		local optpos = tonumber(env.get("_OPTPOS")) or 2
		local ch = arg_val:sub(optpos, optpos)
		if ch == "" then
			-- Move to next arg
			optind = optind + 1
			env.set("OPTIND", tostring(optind))
			env.set("_OPTPOS", "2")
			if optind > #params then
				env.set(varname, "?")
				return 1
			end
			arg_val = params[optind]
			if not arg_val or arg_val:sub(1, 1) ~= "-" or arg_val == "-" or arg_val == "--" then
				env.set(varname, "?")
				return 1
			end
			optpos = 2
			ch = arg_val:sub(optpos, optpos)
		end
		-- Check if ch is in optstring
		local colon_start = optstring:sub(1, 1) == ":"
		local idx = optstring:find(ch, 1, true)
		if not idx then
			-- Unknown option
			env.set(varname, "?")
			env.unset("OPTARG")
			if not colon_start then
				unistd.write(2, "sh: illegal option -- " .. ch .. "\n")
			else
				env.set("OPTARG", ch)
			end
			if optpos < #arg_val then
				env.set("_OPTPOS", tostring(optpos + 1))
			else
				env.set("OPTIND", tostring(optind + 1))
				env.set("_OPTPOS", "2")
			end
			return 0
		end
		-- Check if option takes an argument
		if idx < #optstring and optstring:sub(idx + 1, idx + 1) == ":" then
			-- Needs argument
			if optpos < #arg_val then
				-- Rest of current arg is the argument
				env.set("OPTARG", arg_val:sub(optpos + 1))
			else
				-- Next arg is the argument
				optind = optind + 1
				if optind > #params then
					env.set(varname, colon_start and ":" or "?")
					env.set("OPTARG", ch)
					if not colon_start then
						unistd.write(2, "sh: option requires an argument -- " .. ch .. "\n")
					end
					env.set("OPTIND", tostring(optind))
					env.set("_OPTPOS", "2")
					return 0
				end
				env.set("OPTARG", params[optind])
			end
			env.set("OPTIND", tostring(optind + 1))
			env.set("_OPTPOS", "2")
		else
			-- No argument
			env.unset("OPTARG")
			if optpos < #arg_val then
				env.set("_OPTPOS", tostring(optpos + 1))
			else
				env.set("OPTIND", tostring(optind + 1))
				env.set("_OPTPOS", "2")
			end
		end
		env.set(varname, ch)
		return 0
	end,
	read = function(args)
		-- parse options
		local raw = false
		local vars = {}
		local i = 2
		while i <= #args do
			if args[i] == "-r" then raw = true
			elseif args[i]:sub(1, 1) ~= "-" then
				for j = i, #args do vars[#vars + 1] = args[j] end
				break
			end
			i = i + 1
		end
		if #vars == 0 then vars[1] = "REPLY" end
		-- read one line from stdin
		local buf = {}
		while true do
			local ch = unistd.read(0, 1)
			if not ch or ch == "" then
				-- EOF
				if #buf == 0 then
					for _, v in ipairs(vars) do env.set(v, "") end
					return 1
				end
				break
			end
			if ch == "\n" then break end
			if not raw and ch == "\\" then
				local nxt = unistd.read(0, 1)
				if not nxt or nxt == "" then break end
				if nxt == "\n" then goto continue end -- line continuation
				buf[#buf + 1] = nxt
			else
				buf[#buf + 1] = ch
			end
			::continue::
		end
		local line = table.concat(buf)
		-- field splitting using IFS
		local ifs = env.get("IFS")
		if ifs == nil then ifs = " \t\n" end
		if ifs == "" then
			-- no splitting
			env.set(vars[1], line)
			for j = 2, #vars do env.set(vars[j], "") end
			return 0
		end
		-- split into fields
		local fields = {}
		local pos = 1
		local len = #line
		-- skip leading IFS whitespace
		while pos <= len and ifs:find(line:sub(pos, pos), 1, true) and
			(line:sub(pos, pos) == " " or line:sub(pos, pos) == "\t" or line:sub(pos, pos) == "\n") do
			pos = pos + 1
		end
		while pos <= len and #fields < #vars - 1 do
			local start = pos
			while pos <= len and not ifs:find(line:sub(pos, pos), 1, true) do
				pos = pos + 1
			end
			fields[#fields + 1] = line:sub(start, pos - 1)
			-- skip IFS delimiters
			if pos <= len then
				-- skip one non-whitespace IFS char or whitespace IFS chars
				local c = line:sub(pos, pos)
				if c == " " or c == "\t" or c == "\n" then
					while pos <= len and ifs:find(line:sub(pos, pos), 1, true) and
						(line:sub(pos, pos) == " " or line:sub(pos, pos) == "\t" or line:sub(pos, pos) == "\n") do
						pos = pos + 1
					end
				else
					pos = pos + 1
					-- also skip surrounding whitespace
					while pos <= len and (line:sub(pos, pos) == " " or line:sub(pos, pos) == "\t") do
						pos = pos + 1
					end
				end
			end
		end
		-- last var gets the rest (with trailing IFS whitespace stripped)
		if pos <= len then
			local rest = line:sub(pos)
			rest = rest:gsub("[%s]+$", "")
			fields[#fields + 1] = rest
		end
		-- assign to variables
		for j, v in ipairs(vars) do
			env.set(v, fields[j] or "")
		end
		return 0
	end,
	exit = function(args)
		os.exit(tonumber(args[2]) or tonumber(env.get("?")) or 0)
	end,
	exec = function(args)
		if #args < 2 then
			return 0
		end
		local path = find_in_path(args[2])
		if not path then
			unistd.write(2, "sh: " .. args[2] .. ": command not found\n")
			return 127
		end
		local rest = {}
		for i = 3, #args do
			rest[#rest + 1] = args[i]
		end
		unistd.execp(path, rest)
		return 126
	end,
	cd = function(args)
		local dir = args[2] or env.get("HOME") or "/"
		local ok, err = unistd.chdir(dir)
		if ok == 0 then
			env.set("PWD", unistd.getcwd())
			return 0
		end
		unistd.write(2, "sh: cd: " .. (err or dir .. ": No such file or directory") .. "\n")
		return 1
	end,
	umask = function(args)
		local stat = require("posix.sys.stat")
		if not args[2] then
			-- display current umask
			local cur = stat.umask(0)
			stat.umask(cur)
			unistd.write(1, string.format("%04o\n", cur))
		else
			local mode = tonumber(args[2], 8)
			if not mode then
				unistd.write(2, "sh: umask: " .. args[2] .. ": invalid mode\n")
				return 1
			end
			stat.umask(mode)
		end
		return 0
	end,
	wait = function(args)
		if args[2] then
			local pid = tonumber(args[2])
			if pid then
				local _, reason, status = wait.wait(pid)
				if reason == "exited" then
					return status
				end
				if reason == "killed" then
					return 128 + status
				end
			end
			return 127
		end
		-- wait for all children
		while true do
			local pid, reason, status = wait.wait(-1)
			if not pid or pid == -1 then
				break
			end
		end
		return 0
	end,
}

builtins["type"] = function(args)
	for i = 2, #args do
		local name = args[i]
		local walker = require("sh.walk")
		if walker.functions[name] then
			unistd.write(1, name .. " is a function\n")
		elseif builtins[name] then
			unistd.write(1, name .. " is a shell builtin\n")
		else
			local p = env.get("PATH") or "/bin:/usr/bin"
			local found
			for dir in p:gmatch("[^:]+") do
				local full = dir .. "/" .. name
				if unistd.access(full, "x") == 0 then found = full; break end
			end
			if found then
				unistd.write(1, name .. " is " .. found .. "\n")
			else
				unistd.write(2, "sh: type: " .. name .. ": not found\n")
				return 1
			end
		end
	end
	return 0
end

-- expand all words in a segment and handle leading assignments
-- returns assignments, expanded args, redirections
local function expand_segment(args)
	local assignments = {}
	local i = 1
	-- collect leading NAME=value words
	while i <= #args and expand.is_assignment(args[i]) do
		assignments[#assignments + 1] = args[i]
		i = i + 1
	end
	-- expand remaining words (with glob expansion)
	local expanded = {}
	for j = i, #args do
		local words = expand.glob_word(args[j])
		for _, w in ipairs(words) do
			expanded[#expanded + 1] = w
		end
	end
	-- parse redirections from expanded args
	local clean, redirs = parse_redirections(expanded)
	return assignments, clean, redirs
end

-- execute a pipeline: array of args-arrays
-- returns exit status of last command
local function execute(pipeline)
	if #pipeline == 0 or (#pipeline == 1 and #pipeline[1] == 0) then
		return 0
	end

	-- single command: check for pure assignment or builtin
	if #pipeline == 1 then
		local assignments, args, redirs = expand_segment(pipeline[1])
		-- pure assignment (no command word)
		if #args == 0 then
			for _, a in ipairs(assignments) do
				local name, val = expand.parse_assignment(a)
				local expanded = expand.word(val)
				if env.get_opt("x") then
					trace({ name .. "=" .. expanded })
				end
				env.set(name, expanded)
			end
			return 0
		end
		-- builtin
		if builtins[args[1]] then
			for _, a in ipairs(assignments) do
				local name, val = expand.parse_assignment(a)
				env.set(name, expand.word(val))
			end
			trace(args)
			local saved = apply_redirections(redirs)
			local status = builtins[args[1]](args)
			if saved then
				restore_redirections(saved)
			end
			return status
		end
	end

	local n = #pipeline
	local pids = {}
	local prev_r = nil

	for i, raw_args in ipairs(pipeline) do
		local _, args, redirs = expand_segment(raw_args)

		local r, w
		if i < n then
			r, w = unistd.pipe()
		end

		local pid = unistd.fork()
		if pid == 0 then
			if prev_r then
				unistd.dup2(prev_r, 0)
				unistd.close(prev_r)
			end
			if w then
				unistd.dup2(w, 1)
				unistd.close(w)
			end
			if r then
				unistd.close(r)
			end

			apply_redirections(redirs)

			if #args == 0 then
				os.exit(0)
			end
			trace(args)
			if builtins[args[1]] then
				os.exit(builtins[args[1]](args))
			end
			local path = find_in_path(args[1])
			if not path then
				unistd.write(2, "sh: " .. args[1] .. ": command not found\n")
				os.exit(127)
			end
			local rest = {}
			for j = 2, #args do
				rest[#rest + 1] = args[j]
			end
			unistd.execp(path, rest)
			os.exit(127)
		end

		if prev_r then
			unistd.close(prev_r)
		end
		if w then
			unistd.close(w)
		end
		prev_r = r
		pids[i] = pid
	end

	local last_status = 0
	for i, pid in ipairs(pids) do
		local _, reason, status = wait.wait(pid)
		if i == n then
			if reason == "exited" then
				last_status = status
			elseif reason == "killed" then
				last_status = 128 + status
			else
				last_status = 1
			end
		end
	end
	return last_status
end

return { execute = execute, get_builtins = function() return builtins end }
