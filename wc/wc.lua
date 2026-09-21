#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")

local want_lines, want_words, want_bytes, want_chars = false, false, false, false
local optind = 1

for opt, _, oi in unistd.getopt(arg, "clmw") do
	if opt == "c" then want_bytes = true
	elseif opt == "l" then want_lines = true
	elseif opt == "m" then want_chars = true
	elseif opt == "w" then want_words = true
	else
		io.stderr:write("usage: wc [-c|-m] [-lw] [file...]\n")
		os.exit(2)
	end
	optind = oi
end
if arg[optind] == "--" then optind = optind + 1 end

if not (want_lines or want_words or want_bytes or want_chars) then
	want_lines, want_words, want_bytes = true, true, true
end

local files = {}
for i = optind, #arg do
	files[#files + 1] = arg[i]
end

local total_l, total_w, total_b, total_m = 0, 0, 0, 0

local function report(l, w, b, m, name)
	local out = {}
	if want_lines then out[#out + 1] = string.format("%8d", l) end
	if want_words then out[#out + 1] = string.format("%8d", w) end
	if want_bytes then out[#out + 1] = string.format("%8d", b) end
	if want_chars then out[#out + 1] = string.format("%8d", m) end
	print(table.concat(out) .. " " .. name)
end

local function process(name, text)
	local l = select(2, text:gsub("\n", ""))
	local w = select(2, text:gsub("%S+", ""))
	local b = #text
	local m = utf8.len(text) or b
	total_l, total_w, total_b, total_m = total_l + l, total_w + w, total_b + b, total_m + m
	report(l, w, b, m, name)
end

if #files == 0 then
	process("", io.read("*a"))
else
	for _, path in ipairs(files) do
		local f, err = io.open(path, "rb")
		if not f then
			io.stderr:write("wc: " .. path .. ": " .. err .. "\n")
			os.exit(1)
		end
		process(path, f:read("*a"))
		f:close()
	end
	if #files > 1 then
		report(total_l, total_w, total_b, total_m, "total")
	end
end
