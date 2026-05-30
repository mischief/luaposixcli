-- SPDX-License-Identifier: ISC
-- make/jobserver.lua - parallel job scheduler with token pool
local unistd = require("posix.unistd")
local wait = require("posix.sys.wait")
local fcntl = require("posix.fcntl")
local poll = require("posix.poll")

local M = {}

-- Create a new jobserver (top-level make)
-- maxjobs: maximum concurrent jobs
function M.new(maxjobs)
	local self = {
		maxjobs = maxjobs,
		pipe_r = nil, -- read end of token pipe
		pipe_w = nil, -- write end of token pipe
		owned = false, -- did we create the pipe?
		running = {}, -- pid -> {target, out_r, err_r}
		nrunning = 0, -- count of running jobs
	}
	return setmetatable(self, { __index = M })
end

-- Create the token pipe and fill it with tokens
function M:create_pool()
	local r, w = unistd.pipe()
	self.pipe_r = r
	self.pipe_w = w
	self.owned = true
	-- Write maxjobs-1 tokens (we always have one "free" slot)
	for _ = 1, self.maxjobs - 1 do
		unistd.write(w, "+")
	end
	-- Set pipe read to non-blocking for polling
	local flags = fcntl.fcntl(r, fcntl.F_GETFL)
	fcntl.fcntl(r, fcntl.F_SETFL, flags + fcntl.O_NONBLOCK)
end

-- Inherit an existing jobserver pipe from parent make
function M:inherit(read_fd, write_fd)
	-- Verify the FDs are valid
	local flags = fcntl.fcntl(read_fd, fcntl.F_GETFL)
	if not flags then return false end
	flags = fcntl.fcntl(write_fd, fcntl.F_GETFL)
	if not flags then return false end
	self.pipe_r = read_fd
	self.pipe_w = write_fd
	self.owned = false
	-- Set read to non-blocking
	local rflags = fcntl.fcntl(read_fd, fcntl.F_GETFL)
	fcntl.fcntl(read_fd, fcntl.F_SETFL, rflags + fcntl.O_NONBLOCK)
	return true
end

-- Acquire a token (returns true if acquired, false if would block)
function M:acquire()
	local tok = unistd.read(self.pipe_r, 1)
	if tok and #tok == 1 then return true end
	return false
end

-- Release a token back to the pool
function M:release()
	unistd.write(self.pipe_w, "+")
end

-- Close the pipe (only if we own it)
function M:close()
	if self.owned then
		unistd.close(self.pipe_r)
		unistd.close(self.pipe_w)
	end
end

-- Get the FD string for MAKEFLAGS (e.g. "3,4")
function M:fd_string()
	return tostring(self.pipe_r) .. "," .. tostring(self.pipe_w)
end

-- Launch a job for a target. Recipes run sequentially within the child.
-- Output is captured via pipes and printed atomically on completion.
-- Returns the child PID.
function M:launch(target, recipes, env, silent, ignore)
	-- Create output capture pipes
	local out_r, out_w = unistd.pipe()

	local pid = unistd.fork()
	if pid == 0 then
		-- Child: redirect stdout and stderr to capture pipe
		unistd.close(out_r)
		unistd.dup2(out_w, 1)
		unistd.dup2(out_w, 2)
		unistd.close(out_w)

		-- Close jobserver pipe read end in non-submake children
		-- (submakes will inherit them)
		-- We leave them open here since recipes might invoke $(MAKE)

		-- Execute recipes sequentially
		local shell = env:get("SHELL")
		for _, recipe in ipairs(recipes) do
			local expanded = env:expand(recipe)
			-- Parse prefixes
			local line_silent = silent
			local line_ignore = ignore
			while expanded ~= "" and (expanded:sub(1, 1) == "@"
				or expanded:sub(1, 1) == "-" or expanded:sub(1, 1) == "+") do
				local c = expanded:sub(1, 1)
				if c == "@" then line_silent = true
				elseif c == "-" then line_ignore = true end
				expanded = expanded:sub(2):match("^%s*(.*)") or ""
			end
			if expanded == "" then goto continue end

			if not line_silent then
				unistd.write(1, expanded .. "\n")
			end

			local cpid = unistd.fork()
			if cpid == 0 then
				local shell_args
				if line_ignore then
					shell_args = { "-c", expanded }
				else
					shell_args = { "-e", "-c", expanded }
				end
				unistd.execp(shell, shell_args)
				os.exit(127)
			end
			local _, reason, status = wait.wait(cpid)
			if reason == "exited" and status ~= 0 and not line_ignore then
				os.exit(status)
			elseif reason == "killed" and not line_ignore then
				os.exit(128 + status)
			end
			::continue::
		end
		os.exit(0)
	end

	-- Parent
	unistd.close(out_w)
	self.running[pid] = { target = target, out_r = out_r }
	self.nrunning = self.nrunning + 1
	return pid
end

-- Wait for any one running job to complete.
-- Returns: target, success, output
function M:wait_any()
	if self.nrunning == 0 then return nil end

	-- Wait for any child
	local pid, reason, status = wait.wait(-1)
	if not pid or pid <= 0 then return nil end

	local job = self.running[pid]
	if not job then return nil end

	-- Read all captured output
	local chunks = {}
	while true do
		local data = unistd.read(job.out_r, 4096)
		if not data or data == "" then break end
		chunks[#chunks + 1] = data
	end
	unistd.close(job.out_r)

	self.running[pid] = nil
	self.nrunning = self.nrunning - 1

	local success = (reason == "exited" and status == 0)
	return job.target, success, table.concat(chunks)
end

-- Wait for all running jobs to complete.
-- Returns list of {target, success, output}
function M:wait_all()
	local results = {}
	while self.nrunning > 0 do
		local target, success, output = self:wait_any()
		if target then
			results[#results + 1] = { target = target, success = success, output = output }
		end
	end
	return results
end

-- Parallel build scheduler.
-- Builds the given targets using the dependency graph in executor.
-- executor: the exec module instance (has rules, phony, etc.)
-- targets: list of top-level targets to build
-- Returns true if all succeeded.
function M:build_parallel(executor, targets)
	local stat = require("posix.sys.stat")
	local function mtime(path)
		local s = stat.stat(path)
		return s and s.st_mtime or nil
	end

	-- Build reverse dependency map and compute in-degree
	-- First, collect all targets reachable from the requested targets
	local all_targets = {} -- target -> true
	local deps = {} -- target -> {prereqs}
	local rdeps = {} -- target -> {dependents}
	local recipes_for = {} -- target -> {recipes, silent, ignore, stem}

	local function collect(target)
		if all_targets[target] then return end
		all_targets[target] = true
		rdeps[target] = rdeps[target] or {}

		local rule = executor.rules[target]
		if not rule then
			-- Try pattern/inference rules
			rule = executor:find_pattern_rule(target)
			if not rule then rule = executor:find_inference_rule(target) end
			if rule then executor.rules[target] = rule end
		end

		if not rule then
			deps[target] = {}
			recipes_for[target] = nil
			return
		end

		deps[target] = {}
		for _, p in ipairs(rule.prereqs) do
			deps[target][#deps[target] + 1] = p
			rdeps[p] = rdeps[p] or {}
			rdeps[p][#rdeps[p] + 1] = target
			collect(p)
		end
		recipes_for[target] = {
			recipes = rule.recipes,
			silent = executor.opts.silent or rule.silent,
			ignore = executor.opts.ignore_errors or rule.ignore_errors,
			stem = rule.stem,
		}
	end

	for _, t in ipairs(targets) do collect(t) end

	-- Compute initial "ready" set (targets with all prereqs satisfied)
	local done = {} -- target -> true
	local failed = {} -- target -> true
	local ready = {} -- queue
	local in_flight = {} -- target -> true

	local function is_ready(target)
		if done[target] or in_flight[target] then return false end
		for _, p in ipairs(deps[target] or {}) do
			if not done[p] then return false end
		end
		return true
	end

	local function needs_build(target)
		if executor.phony[target] then return true end
		local t_time = mtime(target)
		if not t_time then return true end
		for _, p in ipairs(deps[target] or {}) do
			local pt = mtime(p)
			if pt and pt > t_time then return true end
		end
		return false
	end

	-- Seed ready queue in prerequisite order (depth-first, leaves first)
	local queued = {}
	local function seed(target)
		if queued[target] then return end
		queued[target] = true
		for _, p in ipairs(deps[target] or {}) do
			seed(p)
		end
		if is_ready(target) then
			ready[#ready + 1] = target
		end
	end
	for _, t in ipairs(targets) do seed(t) end

	-- Main scheduler loop
	local all_ok = true

	while true do
		-- Check if we're done
		local all_done = true
		for _, t in ipairs(targets) do
			if not done[t] and not failed[t] then all_done = false; break end
		end
		if all_done then break end

		-- Launch ready jobs (up to available tokens)
		while #ready > 0 and self.nrunning < self.maxjobs do
			local target = table.remove(ready, 1)
			if done[target] or failed[target] or in_flight[target] then
				goto next_ready
			end

			-- Check if any prereq failed
			local prereq_failed = false
			for _, p in ipairs(deps[target] or {}) do
				if failed[p] then prereq_failed = true; break end
			end
			if prereq_failed then
				failed[target] = true
				all_ok = false
				goto next_ready
			end

			-- Check if target needs building
			if not needs_build(target) then
				done[target] = true
				-- Unblock dependents
				for _, dep in ipairs(rdeps[target] or {}) do
					if is_ready(dep) then ready[#ready + 1] = dep end
				end
				goto next_ready
			end

			-- No recipes = just mark done
			local info = recipes_for[target]
			if not info or #info.recipes == 0 then
				done[target] = true
				for _, dep in ipairs(rdeps[target] or {}) do
					if is_ready(dep) then ready[#ready + 1] = dep end
				end
				goto next_ready
			end

			-- Need a token (first job is free, subsequent need tokens)
			if not executor.opts.dry_run and not executor.opts.question
				and not executor.opts.touch and self.nrunning > 0 then
				if not self:acquire() then break end -- no token available, wait
			end

			-- Set automatic variables for this target
			local rule = executor.rules[target]
			executor.env:set("@", target, "simple", "automatic")
			executor.env:set("<", (rule.prereqs[1] or ""), "simple", "automatic")
			executor.env:set("^", table.concat(rule.prereqs, " "), "simple", "automatic")
			executor.env:set("+", table.concat(rule.prereqs, " "), "simple", "automatic")
			executor.env:set("*", info.stem or "", "simple", "automatic")
			local t_time = mtime(target)
			local newer = {}
			for _, p in ipairs(rule.prereqs) do
				local pt = mtime(p)
				if pt and (not t_time or pt > t_time) then newer[#newer + 1] = p end
			end
			executor.env:set("?", table.concat(newer, " "), "simple", "automatic")

			if executor.opts.question then
				-- Question mode: target is out-of-date, report failure
				all_ok = false
				done[target] = true
				for _, dep in ipairs(rdeps[target] or {}) do
					if is_ready(dep) then ready[#ready + 1] = dep end
				end
			elseif executor.opts.touch then
				-- Touch mode
				if not executor.phony[target] then
					io.stdout:write("touch " .. target .. "\n")
					local f = io.open(target, "a")
					if f then f:close() end
				end
				done[target] = true
				for _, dep in ipairs(rdeps[target] or {}) do
					if is_ready(dep) then ready[#ready + 1] = dep end
				end
			elseif executor.opts.dry_run then
				-- Dry-run: print expanded recipes
				for _, recipe in ipairs(info.recipes) do
					local expanded = executor.env:expand(recipe)
					local line_force = false
					while expanded ~= "" and (expanded:sub(1, 1) == "@"
						or expanded:sub(1, 1) == "-" or expanded:sub(1, 1) == "+") do
						if expanded:sub(1, 1) == "+" then line_force = true end
						expanded = expanded:sub(2):match("^%s*(.*)") or ""
					end
					if expanded ~= "" then
						io.stdout:write(expanded .. "\n")
					end
				end
				done[target] = true
				for _, dep in ipairs(rdeps[target] or {}) do
					if is_ready(dep) then ready[#ready + 1] = dep end
				end
			else
				-- Normal execution: fork
				in_flight[target] = true
				executor.current_target = target
				self:launch(target, info.recipes, executor.env, info.silent, info.ignore)
			end

			::next_ready::
		end

		-- If nothing running and nothing ready, we might be stuck
		if self.nrunning == 0 and #ready == 0 then
			-- Check if there are unreachable targets
			for _, t in ipairs(targets) do
				if not done[t] and not failed[t] then
					io.stderr:write("make: *** No rule to make target '" .. t .. "'. Stop.\n")
					failed[t] = true
					all_ok = false
				end
			end
			break
		end

		-- Wait for a job to finish
		if self.nrunning > 0 then
			local target, success, output = self:wait_any()
			if target then
				-- Print captured output atomically
				if output and output ~= "" then
					unistd.write(1, output)
				end

				-- Release token (if this wasn't the free slot)
				if self.nrunning > 0 then
					-- We still have jobs running, so this was a token-using job
					self:release()
				end

				if success then
					done[target] = true
					in_flight[target] = nil
					-- Unblock dependents
					for _, dep in ipairs(rdeps[target] or {}) do
						if is_ready(dep) then ready[#ready + 1] = dep end
					end
				else
					failed[target] = true
					in_flight[target] = nil
					all_ok = false
					if not executor.opts.keep_going then
						-- Drain remaining jobs
						local remaining = self:wait_all()
						for _, r in ipairs(remaining) do
							if r.output and r.output ~= "" then
								unistd.write(1, r.output)
							end
							self:release()
						end
						break
					end
				end
			end
		end
	end

	executor.current_target = nil
	return all_ok
end

return M
