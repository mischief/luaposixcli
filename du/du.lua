#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local dirent = require("posix.dirent")
local stat = require("posix.sys.stat")

local summary_only = false
local human = false
local block_size = 512
local all = false
local total = false
local optind = 1

for opt, _, oi in unistd.getopt(arg, "ashk") do
	if opt == "a" then all = true
	elseif opt == "s" then summary_only = true
	elseif opt == "h" then human = true
	elseif opt == "k" then block_size = 1024
	else
		unistd.write(2, "usage: du [-ahks] [file...]\n")
		os.exit(2)
	end
	optind = oi
end
if arg[optind] == "--" then optind = optind + 1 end

if all and summary_only then
	unistd.write(2, "du: -a and -s cannot be given together\n")
	os.exit(2)
end

local function format_size(bytes)
	local blocks = math.ceil(bytes / block_size)
	if not human then return tostring(blocks) end
	if bytes >= 1073741824 then return string.format("%.1fG", bytes / 1073741824)
	elseif bytes >= 1048576 then return string.format("%.1fM", bytes / 1048576)
	elseif bytes >= 1024 then return string.format("%.1fK", bytes / 1024)
	else return tostring(bytes) end
end

local function du(path)
	local s = stat.lstat(path)
	if not s then return 0 end

	if stat.S_ISDIR(s.st_mode) ~= 0 then
		local total_bytes = s.st_blocks and s.st_blocks * 512 or 0
		local entries = dirent.dir(path)
		if entries then
			for _, name in ipairs(entries) do
				if name ~= "." and name ~= ".." then
					local child = path .. "/" .. name
					local child_bytes = du(child)
					total_bytes = total_bytes + child_bytes
				end
			end
		end
		if not summary_only then
			unistd.write(1, format_size(total_bytes) .. "\t" .. path .. "\n")
		end
		return total_bytes
	else
		local bytes = s.st_blocks and s.st_blocks * 512 or s.st_size
		-- -a counts every file, not just the directories over them
		if all then
			unistd.write(1, format_size(bytes) .. "\t" .. path .. "\n")
		end
		return bytes
	end
end

local paths = {}
for i = optind, #arg do paths[#paths + 1] = arg[i] end
if #paths == 0 then paths[1] = "." end

local grand_total = 0
for _, p in ipairs(paths) do
	local bytes = du(p)
	if summary_only then
		unistd.write(1, format_size(bytes) .. "\t" .. p .. "\n")
	end
	grand_total = grand_total + bytes
end

if total then
	unistd.write(1, format_size(grand_total) .. "\ttotal\n")
end
