#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
-- fetch - an HTTP GET. The body goes to standard output and nothing
-- else does, so a pipe and a redirect both behave.
-- https is not here: it needs a TLS stack.
local prefix = ((arg[0] or "fetch"):match("(.+/)") or "./") .. "../"
package.path = prefix .. "?.lua;" .. prefix .. "share/lua/5.4/?.lua;" .. package.path

local unistd = require("posix.unistd")
local http = require("luaposixcli.http")
local tcp = require("luaposixcli.tcp")
local util = require("luaposixcli.util")

local showhead, tofile, quiet = false, false, false
local url, optind = nil, 1

while optind <= #arg do
	local a = arg[optind]
	if a == "--" then
		optind = optind + 1
		break
	elseif a:sub(1, 1) == "-" and #a > 1 then
		for c in a:sub(2):gmatch(".") do
			if c == "i" then showhead = true
			elseif c == "O" then tofile = true
			elseif c == "q" then quiet = true
			else
				unistd.write(2, "usage: fetch [-iOq] url\n")
				os.exit(2)
			end
		end
	else
		break
	end
	optind = optind + 1
end

url = arg[optind]
if not url then
	unistd.write(2, "usage: fetch [-iOq] url\n")
	os.exit(2)
end

-- a bare host is a url with the scheme left off, which is what anyone
-- types first
if not url:match("^%a+://") then
	url = "http://" .. url
end
if url:match("^https://") then
	util.die("https is not supported: no TLS here yet")
end

local out = io.stdout
if tofile then
	local name = util.basename((url:gsub("[?#].*$", "")))
	if name == "" then name = "index.html" end
	local f, err = io.open(name, "wb")
	if not f then util.die(err or (name .. ": cannot write")) end
	out = f
	if not quiet then unistd.write(2, "fetch: writing to " .. name .. "\n") end
end

local opts = {}

if showhead then
	opts.onhead = function(status, headers)
		unistd.write(1, "HTTP " .. tostring(status) .. "\n")
		for k, v in pairs(headers or {}) do
			unistd.write(1, k .. ": " .. v .. "\n")
		end
		unistd.write(1, "\n")
	end
end

-- the body is written as it arrives rather than held whole
opts.sink = function(part)
	out:write(part)
	return true
end

local res, err = http.get(tcp, tcp.dns, url, opts)
if out ~= io.stdout then out:close() end

if not res then
	util.die(tostring(err))
end
if res.status >= 400 then
	util.die("HTTP " .. tostring(res.status), 1)
end
