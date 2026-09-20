#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
-- sz - send files to a ZMODEM receiver on the other end of this terminal
local prefix = ((arg[0] or "sz"):match("(.+/)") or "./") .. "../"
package.path = prefix .. "?.lua;" .. prefix .. "share/lua/5.4/?.lua;" .. package.path

local unistd = require("posix.unistd")
local poll = require("posix.poll")
local time = require("posix.time")
local stat = require("posix.sys.stat")
local zmodem = require("luaposixcli.zmodem")
local term = require("luaposixcli.term")
local util = require("luaposixcli.util")

if #arg == 0 then
	util.die("usage: sz file...", 1)
end
if unistd.isatty(0) ~= 1 then
	util.die("not a terminal", 1)
end

-- The far end is told a name, never a path: a receiver that honours a
-- path writes wherever the sender says, and a sender has no business
-- steering it.
local files, total = {}, 0
for _, path in ipairs(arg) do
	local st = stat.stat(path)
	if not st then util.die(path .. ": no such file") end
	local f, err = io.open(path, "rb")
	if not f then util.die(err or (path .. ": cannot read")) end
	total = total + st.st_size
	-- the reader takes an offset because ZRPOS rewinds: the file is
	-- seeked rather than held, so one read is all that is resident
	files[#files + 1] = {
		name = util.basename(path),
		size = st.st_size,
		read = function(off, n)
			f:seek("set", off)
			return f:read(n) or ""
		end,
	}
end

local function now()
	local ts = time.clock_gettime(time.CLOCK_MONOTONIC)
	return ts.tv_sec * 1000 + ts.tv_nsec // 1000000
end

local line = {
	now = now,
	write = function(data)
		local off = 1
		while off <= #data do
			local n = unistd.write(1, data:sub(off))
			if not n or n <= 0 then error("sz: write failed", 0) end
			off = off + n
		end
	end,
	read = function(ms)
		local ready = poll.poll({ [0] = { events = { IN = true } } },
			ms and math.max(math.floor(ms), 1) or 1000)
		if not ready or ready == 0 then return nil end
		local data = unistd.read(0, 512)
		if not data or data == "" then return nil end
		return data
	end,
}

-- raw, or the terminal rewrites the bytes: \n turned into \r\n corrupts
-- every data frame, and the interrupt character would kill the transfer
-- with the transfer's own traffic.
local tty = term.new()
tty:raw()

local m = zmodem.sender(files, { idle = 15000 })
local ok, res, err = pcall(zmodem.drive, m, line)

-- the receiver says OO after the session; left on the line it reaches
-- the shell that started us, which answers that OO is not a command.
line.read(200)
tty:restore()

if not ok then res, err = nil, tostring(res) end
if not res then util.die(tostring(err)) end
