#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
-- awk/awk.lua - POSIX awk main driver
local src_dir = (arg[0]:match("(.+/)") or "./") .. "../"
package.path = src_dir .. "?.lua;" .. src_dir .. "share/lua/5.4/?.lua;" .. package.path
if not package.cpath:find("build") then
	package.cpath = src_dir .. "build/?.so;" .. src_dir .. "lib/lua/5.4/?.so;" .. package.cpath
end

local unistd = require("posix.unistd")
local fcntl = require("posix.fcntl")
local parser = require("awk.parser")
local eval = require("awk.eval")

local fs_opt, prog_files, assignments, files = nil, {}, {}, {}

-- Parse command line
local optind = 1
for opt, optarg, oi in unistd.getopt(arg, "F:f:v:") do
	if opt == "F" then fs_opt = optarg
	elseif opt == "f" then prog_files[#prog_files + 1] = optarg
	elseif opt == "v" then assignments[#assignments + 1] = optarg
	end
	optind = oi
end

-- Get program source
local src
if #prog_files > 0 then
	local parts = {}
	for _, f in ipairs(prog_files) do
		local fh = f == "-" and io.stdin or io.open(f, "r")
		if not fh then
			io.stderr:write("awk: can't open file " .. f .. "\n")
			os.exit(2)
		end
		parts[#parts + 1] = fh:read("a")
		if f ~= "-" then fh:close() end
	end
	src = table.concat(parts, "\n")
else
	if not arg[optind] then
		io.stderr:write("usage: awk [-F fs] [-v var=val] 'program' [file ...]\n")
		os.exit(1)
	end
	src = arg[optind]
	optind = optind + 1
end

-- Collect file arguments
for i = optind, #arg do files[#files + 1] = arg[i] end

-- Parse program
local ok, ast = pcall(parser.parse, src)
if not ok then
	io.stderr:write("awk: " .. tostring(ast) .. "\n")
	os.exit(2)
end

-- Create interpreter
local interp = eval.new()

-- Apply -F
if fs_opt then interp:set_var("FS", fs_opt) end

-- Apply -v assignments
for _, a in ipairs(assignments) do
	local name, val = a:match("^([%w_]+)=(.*)")
	if name then interp:set_var(name, val) end
end

-- Set up ARGC/ARGV
interp:set_var("ARGC", #files + 1)
local argv = {}
argv["0"] = "awk"
for i, f in ipairs(files) do argv[tostring(i)] = f end
interp.globals["ARGV"] = argv

-- Record reader: reads from files list or stdin
local current_file = nil
local file_idx = 0

local function open_next_file()
	if current_file and current_file ~= io.stdin then current_file:close() end
	file_idx = file_idx + 1
	if file_idx > #files then
		if file_idx == 1 then
			-- no files specified, use stdin
			current_file = io.stdin
			interp.filename = ""
			interp.fnr = 0
			return true
		end
		return false
	end
	local fname = files[file_idx]
	-- Check for assignment operand
	local name, val = fname:match("^([%a_][%w_]*)=(.*)")
	if name then
		interp:set_var(name, val)
		return open_next_file()
	end
	if fname == "-" then
		current_file = io.stdin
		interp.filename = "-"
	else
		current_file = io.open(fname, "r")
		if not current_file then
			io.stderr:write("awk: can't open file " .. fname .. "\n")
			os.exit(2)
		end
		interp.filename = fname
	end
	interp.fnr = 0
	return true
end

local file_opened = false
local function get_record()
	if not file_opened then
		if not open_next_file() then return nil end
		file_opened = true
	end
	while true do
		local line = current_file:read("l")
		if line then return line end
		-- Try next file
		if not open_next_file() then return nil end
	end
end

-- Run
local exit_code = interp:run(ast, get_record)
os.exit(exit_code)
