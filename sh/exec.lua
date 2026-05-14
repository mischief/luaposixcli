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

return { execute = execute }
