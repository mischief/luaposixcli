#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local fcntl = require("posix.fcntl")

local page_len = 66
local header_lines = 5
local trailer_lines = 5
local body_lines = page_len - header_lines - trailer_lines
local files = {}

for _, a in ipairs(arg) do
	files[#files + 1] = a
end
if #files == 0 then
	files = { "-" }
end

for _, file in ipairs(files) do
	local fd = 0
	if file ~= "-" then
		fd = fcntl.open(file, fcntl.O_RDONLY)
		if not fd then
			unistd.write(2, "pr: " .. file .. ": No such file or directory\n")
			os.exit(1)
		end
	end

	-- read all content
	local content = ""
	while true do
		local data = unistd.read(fd, 8192)
		if not data or data == "" then
			break
		end
		content = content .. data
	end
	if fd ~= 0 then
		unistd.close(fd)
	end

	local lines = {}
	for line in content:gmatch("([^\n]*)\n?") do
		lines[#lines + 1] = line
	end

	local page = 1
	local i = 1
	local date_str = os.date("%b %d %H:%M %Y")
	while i <= #lines do
		-- header
		unistd.write(1, "\n\n")
		unistd.write(1, string.format("%s  %s  Page %d\n", date_str, file, page))
		unistd.write(1, "\n\n")
		-- body
		for _ = 1, body_lines do
			if i <= #lines then
				unistd.write(1, lines[i] .. "\n")
			else
				unistd.write(1, "\n")
			end
			i = i + 1
		end
		-- trailer
		for _ = 1, trailer_lines do
			unistd.write(1, "\n")
		end
		page = page + 1
	end
end
