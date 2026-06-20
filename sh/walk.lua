-- SPDX-License-Identifier: ISC
-- sh/walk.lua: AST tree walker / executor for the POSIX shell
local unistd = require("posix.unistd")
local wait = require("posix.sys.wait")
local fcntl = require("posix.fcntl")
local signal = require("posix.signal")
local stdlib = require("posix.stdlib")
local notposix = require("luaposixcli.sys")
local env = require("sh.env")
local expand = require("sh.expand")

local M = {}

-- Shell's process group (for terminal control)
local shell_pgid = unistd.getpgrp()
local shell_pid = unistd.getpid()
local is_interactive = unistd.isatty(0) == 1

-- Function table: name -> AST node
local functions = {}


-- Forward declaration
local walk

-- Apply redirections, returns saved FDs for restore
local function apply_redirections(redirs, heredoc_bodies)
	if not redirs or #redirs == 0 then return {} end
	local saved = {}
	for _, r in ipairs(redirs) do
		local fd = r.fd
		if r.op == ">" then
			if not fd then fd = 1 end
			local target = expand.word(r.target)
			local new_fd = fcntl.open(target, fcntl.O_WRONLY + fcntl.O_CREAT + fcntl.O_TRUNC, 438)
			if new_fd then
				saved[#saved + 1] = { fd = fd, saved = unistd.dup(fd) }
				unistd.dup2(new_fd, fd)
				unistd.close(new_fd)
			end
		elseif r.op == ">>" then
			if not fd then fd = 1 end
			local target = expand.word(r.target)
			local new_fd = fcntl.open(target, fcntl.O_WRONLY + fcntl.O_CREAT + fcntl.O_APPEND, 438)
			if new_fd then
				saved[#saved + 1] = { fd = fd, saved = unistd.dup(fd) }
				unistd.dup2(new_fd, fd)
				unistd.close(new_fd)
			end
		elseif r.op == "<" then
			if not fd then fd = 0 end
			local target = expand.word(r.target)
			local new_fd = fcntl.open(target, fcntl.O_RDONLY)
			if new_fd then
				saved[#saved + 1] = { fd = fd, saved = unistd.dup(fd) }
				unistd.dup2(new_fd, fd)
				unistd.close(new_fd)
			end
		elseif r.op == ">&" then
			if not fd then fd = 1 end
			if r.target == "-" then
				unistd.close(fd)
			else
				local src = tonumber(r.target)
				if src then
					saved[#saved + 1] = { fd = fd, saved = unistd.dup(fd) }
					unistd.dup2(src, fd)
				end
			end
		elseif r.op == "<&" then
			if not fd then fd = 0 end
			if r.target == "-" then
				unistd.close(fd)
			else
				local src = tonumber(r.target)
				if src then
					saved[#saved + 1] = { fd = fd, saved = unistd.dup(fd) }
					unistd.dup2(src, fd)
				end
			end
		elseif r.op == "<<" then
			if not fd then fd = 0 end
			local body = ""
			if heredoc_bodies and r.heredoc_idx then
				body = heredoc_bodies[r.heredoc_idx] or ""
			end
			-- Create a pipe, write body, redirect read end to fd
			local pr, pw = unistd.pipe()
			unistd.write(pw, body)
			unistd.close(pw)
			saved[#saved + 1] = { fd = fd, saved = unistd.dup(fd) }
			unistd.dup2(pr, fd)
			unistd.close(pr)
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

-- Find command in PATH
local function find_in_path(cmd)
	if cmd:find("/") then return cmd end
	local path = env.get("PATH") or "/bin:/usr/bin"
	for dir in path:gmatch("[^:]+") do
		local full = dir .. "/" .. cmd
		if unistd.access(full, "x") == 0 then return full end
	end
	return nil
end

-- Trace (set -x)
local function trace(args)
	if not env.get_opt("x") then return end
	local ps4 = env.get("PS4") or "+ "
	unistd.write(2, ps4 .. table.concat(args, " ") .. "\n")
end

-- Builtins table
local builtins

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

local function builtin_unset(args)
	for i = 2, #args do
		env.unset(args[i])
	end
	return 0
end

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

builtins = {
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
			for sig, action in pairs(traps) do
				unistd.write(1, "trap -- '" .. action .. "' " .. sig .. "\n")
			end
			return 0
		end
		local action = args[2]
		local sig_names = {}
		for i = 3, #args do sig_names[#sig_names + 1] = args[i] end
		if #sig_names == 0 then
			sig_names[1] = "EXIT"
		end
		for _, sig in ipairs(sig_names) do
			if action == "" or action == "-" then
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
		if #args < 2 then return 0 end
		local mode = nil
		local start = 2
		if args[2] == "-v" then mode = "v"; start = 3
		elseif args[2] == "-V" then mode = "V"; start = 3
		end
		if mode then
			if not args[start] then return 1 end
			local name = args[start]
			if builtins[name] then
				if mode == "v" then unistd.write(1, name .. "\n")
				else unistd.write(1, name .. " is a shell builtin\n") end
				return 0
			end
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
		local cmd_args = {}
		for i = start, #args do cmd_args[#cmd_args + 1] = args[i] end
		if builtins[cmd_args[1]] then
			return builtins[cmd_args[1]](cmd_args)
		end
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
	["type"] = function(args)
		for i = 2, #args do
			local name = args[i]
			if functions[name] then
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
	end,
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
		if #args < 3 then return 2 end
		local optstring = args[2]
		local varname = args[3]
		local params
		if args[4] then
			params = {}
			for i = 4, #args do params[#params + 1] = args[i] end
		else
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
		local optpos = tonumber(env.get("_OPTPOS")) or 2
		local ch = arg_val:sub(optpos, optpos)
		if ch == "" then
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
		local colon_start = optstring:sub(1, 1) == ":"
		local idx = optstring:find(ch, 1, true)
		if not idx then
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
		if idx < #optstring and optstring:sub(idx + 1, idx + 1) == ":" then
			if optpos < #arg_val then
				env.set("OPTARG", arg_val:sub(optpos + 1))
			else
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
		local buf = {}
		while true do
			local ch = unistd.read(0, 1)
			if not ch or ch == "" then
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
				if nxt == "\n" then goto continue end
				buf[#buf + 1] = nxt
			else
				buf[#buf + 1] = ch
			end
			::continue::
		end
		local line = table.concat(buf)
		local ifs = env.get("IFS")
		if ifs == nil then ifs = " \t\n" end
		if ifs == "" then
			env.set(vars[1], line)
			for j = 2, #vars do env.set(vars[j], "") end
			return 0
		end
		local fields = {}
		local pos = 1
		local len = #line
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
			if pos <= len then
				local c = line:sub(pos, pos)
				if c == " " or c == "\t" or c == "\n" then
					while pos <= len and ifs:find(line:sub(pos, pos), 1, true) and
						(line:sub(pos, pos) == " " or line:sub(pos, pos) == "\t" or line:sub(pos, pos) == "\n") do
						pos = pos + 1
					end
				else
					pos = pos + 1
					while pos <= len and (line:sub(pos, pos) == " " or line:sub(pos, pos) == "\t") do
						pos = pos + 1
					end
				end
			end
		end
		if pos <= len then
			local rest = line:sub(pos)
			rest = rest:gsub("[%s]+$", "")
			fields[#fields + 1] = rest
		end
		for j, v in ipairs(vars) do
			env.set(v, fields[j] or "")
		end
		return 0
	end,
	exit = function(args)
		os.exit(tonumber(args[2]) or tonumber(env.get("?")) or 0)
	end,
	exec = function(args)
		if #args < 2 then return 0 end
		local path = find_in_path(args[2])
		if not path then
			unistd.write(2, "sh: " .. args[2] .. ": command not found\n")
			return 127
		end
		local rest = {}
		for i = 3, #args do rest[#rest + 1] = args[i] end
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
				if reason == "exited" then return status end
				if reason == "killed" then return 128 + status end
			end
			return 127
		end
		while true do
			local pid = wait.wait(-1)
			if not pid or pid == -1 then break end
		end
		return 0
	end,
}

-- Execute a simple command (expand words, handle builtins, fork+exec)
local function exec_simple(node)
	-- Process assignments
	local assigns = node.assigns or {}
	-- Expand words (with glob)
	local args = {}
	for _, w in ipairs(node.words or {}) do
		local expanded = expand.glob_word(w)
		for _, e in ipairs(expanded) do args[#args + 1] = e end
	end

	-- Pure assignment (no command)
	if #args == 0 then
		for _, a in ipairs(assigns) do
			local name, val = expand.parse_assignment(a)
			local expanded_val = expand.word(val)
			if env.get_opt("x") then trace({ name .. "=" .. expanded_val }) end
			env.set(name, expanded_val)
		end
		return 0
	end

	trace(args)

	-- Check for shell functions
	if functions[args[1]] then
		-- prefix assignments are temporary for functions
		local saved_vals = {}
		for _, a in ipairs(assigns) do
			local name, val = expand.parse_assignment(a)
			saved_vals[name] = env.get(name)
			env.set(name, expand.word(val))
		end
		local saved = apply_redirections(node.redirs, node.heredoc_bodies)
		local func_node = functions[args[1]]
		-- Save and set positional params
		local old_argv = env.get_argv and env.get_argv() or nil
		local new_argv = { args[1] }
		for i = 2, #args do new_argv[#new_argv + 1] = args[i] end
		env.set_argv(new_argv)
		local status = walk(func_node.body)
		-- Handle return
		if env.get("_return") then
			status = tonumber(env.get("_return")) or 0
			env.unset("_return")
		end
		if old_argv then env.set_argv(old_argv) end
		restore_redirections(saved)
		for name, oldval in pairs(saved_vals) do
			if oldval == nil then env.unset(name) else env.set(name, oldval) end
		end
		return status
	end

	-- Check for builtins
	if builtins[args[1]] then
		-- prefix assignments are temporary for regular builtins
		local saved_vals = {}
		for _, a in ipairs(assigns) do
			local name, val = expand.parse_assignment(a)
			saved_vals[name] = env.get(name)
			env.set(name, expand.word(val))
		end
		local saved = apply_redirections(node.redirs, node.heredoc_bodies)
		local status = builtins[args[1]](args)
		restore_redirections(saved)
		for name, oldval in pairs(saved_vals) do
			if oldval == nil then env.unset(name) else env.set(name, oldval) end
		end
		return status
	end

	-- External command: fork + exec
	local pid = unistd.fork()
	if pid == 0 then
		signal.signal(signal.SIGINT, signal.SIG_DFL)
		signal.signal(signal.SIGQUIT, signal.SIG_DFL)
		-- apply prefix assignments to child environment only
		for _, a in ipairs(assigns) do
			local name, val = expand.parse_assignment(a)
			stdlib.setenv(name, expand.word(val), true)
		end
		apply_redirections(node.redirs, node.heredoc_bodies)
		local path = find_in_path(args[1])
		if not path then
			unistd.write(2, "sh: " .. args[1] .. ": command not found\n")
			os.exit(127)
		end
		local rest = {}
		for i = 2, #args do rest[#rest + 1] = args[i] end
		unistd.execp(path, rest)
		os.exit(127)
	end
	-- Parent: wait for child. Shell's SIGINT handler stays active
	-- (children get SIG_DFL via the fork path above)
	local _, reason, status
	repeat
		_, reason, status = wait.wait(pid)
	until reason ~= nil
	if reason == "exited" then return status
	elseif reason == "killed" then return 128 + status
	else return 1 end
end

-- Execute a pipeline
local function exec_pipeline(node)
	local cmds = node.cmds
	if #cmds == 1 then
		local status = walk(cmds[1])
		if node.bang then status = (status == 0) and 1 or 0 end
		return status
	end

	local n = #cmds
	local pids = {}
	local prev_r = nil

	for i, cmd in ipairs(cmds) do
		local r, w
		if i < n then r, w = unistd.pipe() end

		local pid = unistd.fork()
		if pid == 0 then
			signal.signal(signal.SIGPIPE, signal.SIG_DFL)
			if prev_r then unistd.dup2(prev_r, 0); unistd.close(prev_r) end
			if w then unistd.dup2(w, 1); unistd.close(w) end
			if r then unistd.close(r) end
			local s = walk(cmd)
			os.exit(s)
		end

		if prev_r then unistd.close(prev_r) end
		if w then unistd.close(w) end
		prev_r = r
		pids[i] = pid
	end

	local last_status = 0
	for i, pid in ipairs(pids) do
		local _, reason, status = wait.wait(pid)
		if i == n then
			if reason == "exited" then last_status = status
			elseif reason == "killed" then last_status = 128 + status
			else last_status = 1 end
		end
	end
	if node.bang then last_status = (last_status == 0) and 1 or 0 end
	return last_status
end

-- Walk/execute an AST node. Returns exit status.
function walk(node)
	if not node then return 0 end
	local t = node.type

	if t == "simple" then
		return exec_simple(node)

	elseif t == "pipeline" then
		return exec_pipeline(node)

	elseif t == "and_or" then
		local left_status = walk(node.left)
		env.set_status(left_status)
		if node.op == "&&" then
			if left_status == 0 then return walk(node.right) end
			return left_status
		else -- ||
			if left_status ~= 0 then return walk(node.right) end
			return left_status
		end

	elseif t == "list" then
		local status = 0
		for _, item in ipairs(node.items) do
			if env.get("_break") or env.get("_continue") or env.get("_return") then break end
			status = walk(item)
			env.set_status(status)
		end
		return status

	elseif t == "async" then
		local pid = unistd.fork()
		if pid == 0 then
			local s = walk(node.body)
			os.exit(s)
		end
		env.set_last_bg(pid)
		return 0

	elseif t == "if" then
		local saved = apply_redirections(node.redirs)
		local cond_status = walk(node.cond)
		env.set_status(cond_status)
		local status
		if cond_status == 0 then
			status = walk(node.then_body)
		else
			-- Try elifs
			local matched = false
			for _, elif in ipairs(node.elifs or {}) do
				local es = walk(elif.cond)
				env.set_status(es)
				if es == 0 then
					status = walk(elif.body)
					matched = true
					break
				end
			end
			if not matched then
				status = walk(node.else_body)
			end
		end
		restore_redirections(saved)
		return status or 0

	elseif t == "while" then
		local saved = apply_redirections(node.redirs)
		local status = 0
		while true do
			local cs = walk(node.cond)
			env.set_status(cs)
			if cs ~= 0 then break end
			status = walk(node.body)
			env.set_status(status)
			if env.get("_break") then
				local n = tonumber(env.get("_break"))
				env.unset("_break")
				if n and n > 1 then env.set("_break", tostring(n - 1)) end
				break
			end
			if env.get("_continue") then
				local n = tonumber(env.get("_continue"))
				env.unset("_continue")
				if n and n > 1 then env.set("_continue", tostring(n - 1)); break end
			end
		end
		restore_redirections(saved)
		return status

	elseif t == "until" then
		local saved = apply_redirections(node.redirs)
		local status = 0
		while true do
			local cs = walk(node.cond)
			env.set_status(cs)
			if cs == 0 then break end
			status = walk(node.body)
			env.set_status(status)
			if env.get("_break") then
				local n = tonumber(env.get("_break"))
				env.unset("_break")
				if n and n > 1 then env.set("_break", tostring(n - 1)) end
				break
			end
			if env.get("_continue") then
				local n = tonumber(env.get("_continue"))
				env.unset("_continue")
				if n and n > 1 then env.set("_continue", tostring(n - 1)); break end
			end
		end
		restore_redirections(saved)
		return status

	elseif t == "for" then
		local saved = apply_redirections(node.redirs)
		local wordlist
		if node.wordlist then
			wordlist = {}
			for _, w in ipairs(node.wordlist) do
				local expanded = expand.glob_word(w)
				for _, e in ipairs(expanded) do wordlist[#wordlist + 1] = e end
			end
		else
			-- Default: positional parameters
			local all = env.get("@")
			wordlist = {}
			for w in all:gmatch("%S+") do wordlist[#wordlist + 1] = w end
		end
		local status = 0
		for _, val in ipairs(wordlist) do
			env.set(node.name, val)
			status = walk(node.body)
			env.set_status(status)
			if env.get("_break") then
				local n = tonumber(env.get("_break"))
				env.unset("_break")
				if n and n > 1 then env.set("_break", tostring(n - 1)) end
				break
			end
			if env.get("_continue") then
				local n = tonumber(env.get("_continue"))
				env.unset("_continue")
				if n and n > 1 then env.set("_continue", tostring(n - 1)); break end
			end
		end
		restore_redirections(saved)
		return status

	elseif t == "case" then
		local saved = apply_redirections(node.redirs)
		local word = expand.word(node.word)
		local status = 0
		local compound = require("sh.compound")
		for _, clause in ipairs(node.clauses) do
			for _, pat in ipairs(clause.patterns) do
				local epat = expand.word(pat)
				if compound.case_match(word, epat) then
					if clause.body then
						status = walk(clause.body)
					end
					restore_redirections(saved)
					return status
				end
			end
		end
		restore_redirections(saved)
		return status

	elseif t == "subshell" then
		local pid = unistd.fork()
		if pid == 0 then
			local saved = apply_redirections(node.redirs)
			local s = walk(node.body)
			os.exit(s)
		end
		local _, reason, status = wait.wait(pid)
		if reason == "exited" then return status
		elseif reason == "killed" then return 128 + status
		else return 1 end

	elseif t == "brace" then
		local saved = apply_redirections(node.redirs)
		local status = walk(node.body)
		restore_redirections(saved)
		return status

	elseif t == "function" then
		functions[node.name] = node
		return 0
	end

	return 0
end

M.walk = walk
M.functions = functions
M.get_builtins = function() return builtins end

-- Allow setting the run function for command substitution
function M.set_run_fn(fn)
	-- Not needed with AST walker - expand.lua calls back via walk
end

return M
