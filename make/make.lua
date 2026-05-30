#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
-- make/make.lua - POSIX make utility
local src = (arg[0]:match("(.+/)") or "./") .. "../"
package.path = src .. "?.lua;" .. src .. "share/lua/5.4/?.lua;" .. package.path
if not package.cpath:find("build") then
	package.cpath = src .. "build/?.so;" .. src .. "lib/lua/5.4/?.so;" .. package.cpath
end

local unistd = require("posix.unistd")
local fcntl = require("posix.fcntl")
local stdlib = require("posix.stdlib")
local parser = require("make.parser")
local eval = require("make.eval")
local exec = require("make.exec")

-- Parse command-line options
local makefiles = {}
local targets = {}
local macros = {} -- name -> value
local opts = {
	dry_run = false,
	silent = false,
	ignore_errors = false,
	keep_going = false,
	question = false,
	touch = false,
	env_override = false,
	no_builtin = false,
	print_db = false,
}

-- Parse MAKEFLAGS from environment first
local makeflags_env = stdlib.getenv("MAKEFLAGS")
if makeflags_env and makeflags_env ~= "" then
	-- MAKEFLAGS can be: "flags" or "flags -- macro=val ..."
	local flags_part, macros_part = makeflags_env:match("^(.-)%s+%-%-%s+(.*)")
	if not flags_part then flags_part = makeflags_env end
	-- Parse single-char flags
	for c in flags_part:gmatch(".") do
		if c == "n" then opts.dry_run = true
		elseif c == "s" then opts.silent = true
		elseif c == "i" then opts.ignore_errors = true
		elseif c == "k" then opts.keep_going = true
		elseif c == "S" then opts.keep_going = false
		elseif c == "q" then opts.question = true
		elseif c == "t" then opts.touch = true
		elseif c == "e" then opts.env_override = true
		elseif c == "r" then opts.no_builtin = true
		end
	end
	-- Parse macro definitions after --
	if macros_part then
		for m in macros_part:gmatch("%S+") do
			local name, val = m:match("^([^=]+)=(.*)")
			if name then macros[name] = val end
		end
	end
end

-- Parse command-line arguments using luaposix getopt
local optind = 1
for opt, optarg, oi in unistd.getopt(arg, "einpqrstf:j:kS") do
	if opt == "e" then opts.env_override = true
	elseif opt == "i" then opts.ignore_errors = true
	elseif opt == "n" then opts.dry_run = true
	elseif opt == "p" then opts.print_db = true
	elseif opt == "q" then opts.question = true
	elseif opt == "r" then opts.no_builtin = true
	elseif opt == "s" then opts.silent = true
	elseif opt == "S" then opts.keep_going = false
	elseif opt == "t" then opts.touch = true
	elseif opt == "k" then opts.keep_going = true
	elseif opt == "f" then makefiles[#makefiles + 1] = optarg
	elseif opt == "j" then opts.maxjobs = tonumber(optarg) or 1
	elseif opt == "?" then
		io.stderr:write("make: unknown option\n")
		os.exit(2)
	end
	optind = oi
end

-- Remaining arguments: macro=value or targets
for i = optind, #arg do
	local a = arg[i]
	if a:find("=") then
		local name, val = a:match("^([^=]+)=(.*)")
		macros[name] = val
	else
		targets[#targets + 1] = a
	end
end

-- Construct MAKEFLAGS and export to environment
local function build_makeflags()
	local flags = ""
	if opts.dry_run then flags = flags .. "n" end
	if opts.silent then flags = flags .. "s" end
	if opts.ignore_errors then flags = flags .. "i" end
	if opts.keep_going then flags = flags .. "k" end
	if opts.question then flags = flags .. "q" end
	if opts.touch then flags = flags .. "t" end
	if opts.env_override then flags = flags .. "e" end
	if opts.no_builtin then flags = flags .. "r" end
	-- Add macro definitions
	local macro_parts = {}
	for name, val in pairs(macros) do
		if name ~= "MAKEFLAGS" and name ~= "SHELL" then
			macro_parts[#macro_parts + 1] = name .. "=" .. val
		end
	end
	if #macro_parts > 0 then
		flags = flags .. " -- " .. table.concat(macro_parts, " ")
	end
	return flags
end

-- Export command-line macros to environment for sub-makes
for name, val in pairs(macros) do
	if name ~= "MAKEFLAGS" and name ~= "SHELL" then
		stdlib.setenv(name, val, true)
	end
end

-- Set MAKEFLAGS in environment
local makeflags_val = build_makeflags()
stdlib.setenv("MAKEFLAGS", makeflags_val, true)

-- Read a file into a string
local function read_file(path)
	local fd = fcntl.open(path, fcntl.O_RDONLY)
	if not fd then return nil end
	local chunks = {}
	while true do
		local data = unistd.read(fd, 8192)
		if not data or data == "" then break end
		chunks[#chunks + 1] = data
	end
	unistd.close(fd)
	return table.concat(chunks)
end

-- Find makefile
if #makefiles == 0 then
	if unistd.access("makefile", "r") == 0 then
		makefiles[1] = "makefile"
	elseif unistd.access("Makefile", "r") == 0 then
		makefiles[1] = "Makefile"
	else
		if not opts.print_db then
			io.stderr:write("make: *** No makefile found. Stop.\n")
			os.exit(2)
		end
	end
end

-- Create environment
local env = eval.new()
if not opts.no_builtin then
	env:set_defaults()
end
env:seed_env()

-- Command-line macros override everything
for name, val in pairs(macros) do
	env:set(name, val, "simple", "command")
end

-- Parse and load all makefiles
local all_nodes = {}
for _, mf in ipairs(makefiles) do
	local content = read_file(mf)
	if not content then
		io.stderr:write("make: " .. mf .. ": No such file or directory\n")
		os.exit(2)
	end
	local nodes = parser.parse(content)

	-- Process includes
	local function process_includes(node_list)
		local result = {}
		for _, node in ipairs(node_list) do
			if node.type == "include" then
				local files = env:expand(node.arg)
				local silent_include = node.keyword == "-include" or node.keyword == "sinclude"
				for f in files:gmatch("%S+") do
					local inc_content = read_file(f)
					if inc_content then
						local inc_nodes = parser.parse(inc_content)
						local processed = process_includes(inc_nodes)
						for _, n in ipairs(processed) do result[#result + 1] = n end
					elseif not silent_include then
						io.stderr:write("make: " .. f .. ": No such file or directory\n")
						os.exit(2)
					end
				end
			else
				result[#result + 1] = node
			end
		end
		return result
	end

	nodes = process_includes(nodes)
	for _, n in ipairs(nodes) do all_nodes[#all_nodes + 1] = n end
end

-- Process variable assignments and conditionals
env:load(all_nodes)

-- If -e, environment overrides file variables
if opts.env_override then
	for k, v in pairs(stdlib.getenv()) do
		if type(k) == "string" then env:set(k, v, "simple", "environment_override") end
	end
end

-- Command-line macros always win (re-apply after file processing)
for name, val in pairs(macros) do
	env:set(name, val, "simple", "command")
end

-- Set MAKE variable
env:set("MAKE", arg[0] or "make", "simple", "default")
env:set("MAKEFLAGS", makeflags_val, "simple", "default")

-- Create executor and load rules
local executor = exec.new(env, opts)
executor:load(all_nodes)

-- Add default inference rules if not -r
if not opts.no_builtin then
	executor:add_default_rules()
end

-- Install signal handlers
executor:install_signals()

-- Print database if -p
if opts.print_db then
	io.stdout:write("# Variables\n")
	for name, v in pairs(env.vars) do
		io.stdout:write(name .. " = " .. v.value .. "\n")
	end
	io.stdout:write("\n# Suffixes\n")
	io.stdout:write(".SUFFIXES: " .. table.concat(executor.suffixes, " ") .. "\n")
	io.stdout:write("\n# Inference Rules\n")
	for _, ir in ipairs(executor.inference) do
		if ir.single_suffix then
			io.stdout:write(ir.from_suffix .. ":\n")
		else
			io.stdout:write(ir.from_suffix .. ir.to_suffix .. ":\n")
		end
		for _, r in ipairs(ir.recipes) do
			io.stdout:write("\t" .. r .. "\n")
		end
	end
	io.stdout:write("\n# Rules\n")
	for target, rule in pairs(executor.rules) do
		io.stdout:write(target .. ": " .. table.concat(rule.prereqs, " ") .. "\n")
		for _, r in ipairs(rule.recipes) do
			io.stdout:write("\t" .. r .. "\n")
		end
	end
	os.exit(0)
end

-- Determine targets to build
if #targets == 0 then
	if executor.default_target then
		targets[1] = executor.default_target
	else
		io.stderr:write("make: *** No targets. Stop.\n")
		os.exit(2)
	end
end

-- Build targets
local success = true
do
	local jobserver = require("make.jobserver")
	local maxjobs = opts.maxjobs or 1
	local js = jobserver.new(maxjobs)

	-- Check if we should inherit a jobserver from parent
	local inherited = false
	if makeflags_env then
		local r_fd, w_fd = makeflags_env:match("%-%-jobserver%-fds=(%d+),(%d+)")
		if r_fd then
			inherited = js:inherit(tonumber(r_fd), tonumber(w_fd))
		end
	end
	if not inherited then
		js:create_pool()
	end

	-- Add jobserver FDs to MAKEFLAGS for sub-makes
	local jflags = makeflags_val .. " --jobserver-fds=" .. js:fd_string()
	stdlib.setenv("MAKEFLAGS", jflags, true)
	env:set("MAKEFLAGS", jflags, "simple", "default")

	success = js:build_parallel(executor, targets)
	js:close()
end

if opts.question then
	os.exit(success and 0 or 1)
end
os.exit(success and 0 or 2)
