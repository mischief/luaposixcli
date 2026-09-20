#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local lines_wanted = 10
local bytes_wanted = nil
local from_start = false
local files = {}

local function bad(msg)
	io.stderr:write("tail: " .. msg .. "\n")
	os.exit(2)
end

-- A count may be written +N, which counts from the start of the file
-- rather than the end.
local function count(text)
	local sign, digits = text:match("^([-+]?)(%d+)$")
	if not digits then bad("bad count: " .. text) end
	return tonumber(digits), sign == "+"
end

local i = 1
local no_more_options = false
while i <= #arg do
	local a = arg[i]
	if no_more_options or a == "-" or a:sub(1, 1) ~= "-" then
		files[#files + 1] = a
	elseif a == "--" then
		no_more_options = true
	elseif a:match("^%-%d+$") then
		lines_wanted, from_start = count(a:sub(2))
		bytes_wanted = nil
	elseif a:match("^%-[nc]") then
		local flag = a:sub(2, 2)
		local val = a:sub(3)
		if val == "" then
			i = i + 1
			val = arg[i] or bad("option requires an argument -- " .. flag)
		end
		if flag == "n" then
			lines_wanted, from_start = count(val)
			bytes_wanted = nil
		else
			bytes_wanted, from_start = count(val)
			lines_wanted = nil
		end
	else
		bad("illegal option -- " .. a:sub(2, 2))
	end
	i = i + 1
end

local function tail(f, name, show_header)
	if show_header then
		print("==> " .. name .. " <==")
	end

	if bytes_wanted then
		local data = f:read("a") or ""
		if from_start then
			io.write(data:sub(bytes_wanted))
		else
			io.write(data:sub(#data - bytes_wanted + 1))
		end
		return
	end

	if from_start then
		local n = 0
		while true do
			local line = f:read("L")
			if not line then break end
			n = n + 1
			if n >= lines_wanted then io.write(line) end
		end
		return
	end

	-- the last N lines, holding only those N
	local buf = {}
	while true do
		local line = f:read("L")
		if not line then break end
		buf[#buf + 1] = line
		if #buf > lines_wanted then table.remove(buf, 1) end
	end
	for _, line in ipairs(buf) do io.write(line) end
end

if #files == 0 then
	tail(io.stdin, "", false)
else
	for n, path in ipairs(files) do
		local f, err
		if path == "-" then
			f = io.stdin
		else
			f, err = io.open(path)
			if not f then
				io.stderr:write("tail: " .. path .. ": " .. err .. "\n")
				os.exit(1)
			end
		end
		if n > 1 and #files > 1 then print("") end
		tail(f, path, #files > 1)
		if f ~= io.stdin then f:close() end
	end
end
