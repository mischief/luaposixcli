-- SPDX-License-Identifier: ISC
-- sh/walk.lua: AST tree walker / executor for the POSIX shell
local unistd = require("posix.unistd")
local wait = require("posix.sys.wait")
local fcntl = require("posix.fcntl")
local signal = require("posix.signal")
local notposix = require("notposix")
local env = require("sh.env")
local expand = require("sh.expand")

local M = {}

-- Shell's process group (for terminal control)
local shell_pgid = unistd.getpgrp()
local shell_pid = unistd.getpid()
local is_interactive = unistd.isatty(0) == 1

-- Function table: name -> AST node
local functions = {}

-- Builtins (imported from exec.lua)
local exec_mod = require("sh.exec")

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

	-- Apply prefix assignments
	for _, a in ipairs(assigns) do
		local name, val = expand.parse_assignment(a)
		env.set(name, expand.word(val))
	end

	trace(args)

	-- Check for shell functions
	if functions[args[1]] then
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
		return status
	end

	-- Check for builtins
	local builtins = exec_mod.get_builtins()
	if builtins[args[1]] then
		local saved = apply_redirections(node.redirs, node.heredoc_bodies)
		local status = builtins[args[1]](args)
		restore_redirections(saved)
		return status
	end

	-- External command: fork + exec
	local pid = unistd.fork()
	if pid == 0 then
		signal.signal(signal.SIGINT, signal.SIG_DFL)
		signal.signal(signal.SIGQUIT, signal.SIG_DFL)
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
	-- Parent: ignore SIGINT/SIGQUIT while waiting for foreground child
	local old_int = signal.signal(signal.SIGINT, signal.SIG_IGN)
	local old_quit = signal.signal(signal.SIGQUIT, signal.SIG_IGN)
	local _, reason, status
	repeat
		_, reason, status = wait.wait(pid)
	until reason ~= nil
	signal.signal(signal.SIGINT, old_int)
	signal.signal(signal.SIGQUIT, old_quit)
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

-- Allow setting the run function for command substitution
function M.set_run_fn(fn)
	-- Not needed with AST walker - expand.lua calls back via walk
end

return M
