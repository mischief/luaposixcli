-- SPDX-License-Identifier: ISC
-- luaposixcli/util.lua - what every utility here needs: its own name in a
-- message, and the whole of a file or a descriptor.
local unistd = require("posix.unistd")

local M = {}

function M.basename(path)
	return (path or ""):match("([^/]+)$") or path or ""
end

-- The name a message is prefixed with. A utility installed under several
-- names (gzip, gunzip, zcat) gets the one it was called by.
M.prog = M.basename(arg and arg[0] or ""):gsub("%.lua$", "")

function M.warn(msg)
	unistd.write(2, M.prog .. ": " .. msg .. "\n")
end

function M.die(msg, status)
	M.warn(msg)
	os.exit(status or 1)
end

-- Everything left on a descriptor. Returns nil and the reason on a read
-- error, which is not the same as end of file.
function M.slurp_fd(fd)
	local chunks = {}
	while true do
		local data, err = unistd.read(fd, 65536)
		if not data then return nil, err or "read failed" end
		if data == "" then break end
		chunks[#chunks + 1] = data
	end
	return table.concat(chunks)
end

-- A whole file, or standard input for nil or "-".
function M.slurp(path)
	if path == nil or path == "-" then return M.slurp_fd(0) end
	local f, err = io.open(path, "rb")
	if not f then return nil, err end
	local data = f:read("*a")
	f:close()
	return data
end

-- Lines of a string, blank ones kept, with or without their newline.
function M.lines(text, keep)
	local pos = 1
	return function()
		if pos > #text then return nil end
		local nl = text:find("\n", pos, true)
		local line
		if nl then
			line = text:sub(pos, keep and nl or nl - 1)
			pos = nl + 1
		else
			line = text:sub(pos)
			pos = #text + 1
		end
		return line
	end
end

return M
