#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local lines_wanted = 10
local bytes_wanted = nil
local files = {}

local function bad(msg)
	io.stderr:write("head: " .. msg .. "\n")
	os.exit(2)
end

local function count(text)
	local n = tonumber(text)
	if not n or n < 0 or math.type(n) ~= "integer" then bad("bad count: " .. text) end
	return n
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
		lines_wanted, bytes_wanted = count(a:sub(2)), nil
	elseif a:match("^%-[nc]") then
		local flag = a:sub(2, 2)
		local val = a:sub(3)
		if val == "" then
			i = i + 1
			val = arg[i] or bad("option requires an argument -- " .. flag)
		end
		if flag == "n" then
			lines_wanted, bytes_wanted = count(val), nil
		else
			bytes_wanted, lines_wanted = count(val), nil
		end
	else
		bad("illegal option -- " .. a:sub(2, 2))
	end
	i = i + 1
end

local function head(f, name, show_header)
	if show_header then
		print("==> " .. name .. " <==")
	end
	if bytes_wanted then
		local data = f:read(bytes_wanted)
		if data then io.write(data) end
		return
	end
	local n = 0
	while n < lines_wanted do
		local line = f:read("L")
		if not line then break end
		io.write(line)
		n = n + 1
	end
end

if #files == 0 then
	head(io.stdin, "", false)
else
	for n, path in ipairs(files) do
		local f, err
		if path == "-" then
			f = io.stdin
		else
			f, err = io.open(path)
			if not f then
				io.stderr:write("head: " .. path .. ": " .. err .. "\n")
				os.exit(1)
			end
		end
		if n > 1 and #files > 1 then print("") end
		head(f, path, #files > 1)
		if f ~= io.stdin then f:close() end
	end
end
