-- SPDX-License-Identifier: ISC
-- sh/env.lua: shell variable store
local unistd = require("posix.unistd")

local vars = {} -- name -> value
local exported = {} -- name -> bool
local status = 0
local argv = { "sh" }
local last_bg = ""
local opts = {} -- single-char option flags: opts["x"] = true/false
local traps = {} -- signal name -> action string

-- seed from process environment
local function seed_from_env()
	local f = io.open("/proc/self/environ", "rb")
	if f then
		local data = f:read("*a")
		f:close()
		for entry in data:gmatch("[^%z]+") do
			local k, v = entry:match("^([^=]+)=(.*)")
			if k then
				vars[k] = v
				exported[k] = true
			end
		end
		return
	end
	-- Fallback: use posix.stdlib.getenv()
	local ok, stdlib = pcall(require, "posix.stdlib")
	if ok and stdlib.getenv then
		for k, v in pairs(stdlib.getenv()) do
			if type(k) == "string" then
				vars[k] = v
				exported[k] = true
			end
		end
	end
end

local M = {}

function M.reset()
	vars = {}
	exported = {}
	status = 0
	argv = { "sh" }
	last_bg = ""
	opts = {}
	seed_from_env()
end

function M.set_opt(flag, val)
	opts[flag] = val and true or false
end

function M.get_opt(flag)
	return opts[flag] == true
end

function M.set(name, value)
	vars[name] = value
end

function M.get(name)
	-- special parameters
	if name == "?" then
		return tostring(status)
	end
	if name == "$" then
		return tostring(unistd.getpid())
	end
	if name == "!" then
		return last_bg
	end
	if name == "-" then
		local s = ""
		for k in pairs(opts) do
			if opts[k] then
				s = s .. k
			end
		end
		return s
	end
	if name == "0" then
		return argv[1] or "sh"
	end
	if name == "#" then
		return tostring(#argv - 1)
	end
	-- Numeric positional parameters $1, $2, ...
	local n = tonumber(name)
	if n and n >= 1 then
		return argv[n + 1] or ""
	end
	if name == "@" or name == "*" then
		local t = {}
		for i = 2, #argv do
			t[#t + 1] = argv[i]
		end
		return table.concat(t, " ")
	end
	return vars[name]
end

function M.unset(name)
	vars[name] = nil
	exported[name] = nil
end

function M.export(name)
	exported[name] = true
end

function M.is_exported(name)
	return exported[name] == true
end

function M.set_status(s)
	status = s
end

function M.set_argv(a)
	argv = a
end

function M.get_argv()
	return argv
end

function M.set_last_bg(pid)
	last_bg = tostring(pid)
end

-- returns table of name=value pairs for exported vars
function M.environ()
	local t = {}
	for k, v in pairs(vars) do
		if exported[k] then
			t[#t + 1] = k .. "=" .. v
		end
	end
	return t
end

-- returns iterator over all variables (name, value)
function M.all_vars()
	return pairs(vars)
end

function M.get_traps()
	return traps
end

function M.run_exit_trap()
	local action = traps["EXIT"] or traps["0"]
	if action then
		local run_fn = require("sh.expand").get_run_fn()
		if run_fn then run_fn(action) end
	end
end

M.reset()
return M
