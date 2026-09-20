-- SPDX-License-Identifier: ISC
-- luaposixcli/tcp.lua - the transport luaposixcli.http asks for, over
-- ordinary sockets: dial, send, recv, close, and a resolver.
local socket = require("posix.sys.socket")
local unistd = require("posix.unistd")

local M = {}

-- dial takes the address as four octets because that is what the caller
-- has after parsing a URL or a resolver answer.
function M.dial(a, b, c, d, port, _hostname)
	local fd, err = socket.socket(socket.AF_INET, socket.SOCK_STREAM, 0)
	if not fd then return nil, err end
	local addr = table.concat({ a, b, c, d }, ".")
	local ok, cerr = socket.connect(fd, {
		family = socket.AF_INET,
		addr = addr,
		port = port,
	})
	if not ok then
		unistd.close(fd)
		return nil, cerr or ("cannot connect to " .. addr .. ":" .. port)
	end
	return fd
end

-- Everything or nothing: a short write is not an error to the caller.
function M.send(conn, data)
	local off = 1
	while off <= #data do
		local n, err = socket.send(conn, data:sub(off))
		if not n or n <= 0 then return nil, err end
		off = off + n
	end
	return true
end

-- "" means the far end closed, which is how a body of unknown length ends
function M.recv(conn, n)
	return socket.recv(conn, n or 4096)
end

function M.close(conn)
	unistd.close(conn)
end

M.dns = {
	resolve = function(host)
		local res = socket.getaddrinfo(host, nil, {
			family = socket.AF_INET,
			socktype = socket.SOCK_STREAM,
		})
		if not res or not res[1] then return nil end
		return res[1].addr
	end,
}

return M
