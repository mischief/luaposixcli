#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local wait   = require("posix.sys.wait")

local max_args = nil
local cmd = {"echo"}
local one_per_line = false

local optind = 1
for opt, optarg, oi in unistd.getopt(arg, "n:L:I:") do
	if     opt == "n" then max_args = tonumber(optarg)
	elseif opt == "L" then one_per_line = true; max_args = tonumber(optarg) or 1
	end
	optind = oi
end

if optind <= #arg then
	cmd = {}
	for i = optind, #arg do cmd[#cmd + 1] = arg[i] end
end

-- read all input words
local content = ""
while true do
	local data = unistd.read(0, 8192)
	if not data or data == "" then break end
	content = content .. data
end

local words = {}
for w in content:gmatch("%S+") do
	words[#words + 1] = w
end

-- execute in batches
local function run(args)
	local pid = unistd.fork()
	if pid == 0 then
		local rest = {}
		for i = 2, #args do rest[#rest + 1] = args[i] end
		unistd.execp(args[1], rest)
		os.exit(127)
	end
	local _, reason, status = wait.wait(pid)
	if reason == "exited" then return status end
	return 1
end

local exit_status = 0
local batch = {}
for _, w in ipairs(words) do
	batch[#batch + 1] = w
	if max_args and #batch >= max_args then
		local args = {}
		for _, c in ipairs(cmd) do args[#args + 1] = c end
		for _, b in ipairs(batch) do args[#args + 1] = b end
		local s = run(args)
		if s ~= 0 then exit_status = s end
		batch = {}
	end
end

if #batch > 0 then
	local args = {}
	for _, c in ipairs(cmd) do args[#args + 1] = c end
	for _, b in ipairs(batch) do args[#args + 1] = b end
	local s = run(args)
	if s ~= 0 then exit_status = s end
end

os.exit(exit_status)
