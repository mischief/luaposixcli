-- SPDX-License-Identifier: ISC
-- luaposixcli/utmp.lua - the login records. POSIX describes getutxent and a
-- struct utmpx, but says nothing about the file they come from, and musl
-- answers those calls with nothing at all. The file is the same shape on
-- every Linux, so read it.
local M = {}

M.UTMP = "/var/run/utmp"
M.WTMP = "/var/log/wtmp"

-- The types a record carries. A login is a USER_PROCESS; the record
-- that replaces it when the session ends is a DEAD_PROCESS.
M.EMPTY = 0
M.RUN_LVL = 1
M.BOOT_TIME = 2
M.NEW_TIME = 3
M.OLD_TIME = 4
M.INIT_PROCESS = 5
M.LOGIN_PROCESS = 6
M.USER_PROCESS = 7
M.DEAD_PROCESS = 8
M.ACCOUNTING = 9

-- struct utmp, 384 bytes, as glibc and musl both lay it out. The two
-- pad bytes are what the compiler puts between the short and the pid.
local RECORD = "<i2xxi4c32c4c32c256i2i2i4i4i4i4i4i4i4c20"
M.SIZE = 384

local function trim(text)
	return (text:gsub("%z.*$", ""))
end

-- One record, from a 384 byte string
function M.unpack(data)
	local kind, pid, line, id, user, host, code, status, session,
		sec, usec = string.unpack(RECORD, data)
	return {
		type = kind,
		pid = pid,
		line = trim(line),
		id = trim(id),
		user = trim(user),
		host = trim(host),
		exit_code = code,
		exit_status = status,
		session = session,
		time = sec,
		usec = usec,
	}
end

function M.pack(rec)
	return string.pack(RECORD, rec.type or 0, rec.pid or 0,
		rec.line or "", rec.id or "", rec.user or "", rec.host or "",
		rec.exit_code or 0, rec.exit_status or 0, rec.session or 0,
		rec.time or os.time(), rec.usec or 0, 0, 0, 0, 0, "")
end

-- Every record in a file, oldest first. A file that is not there is not
-- an error: a machine that has never had a login has no utmp.
function M.read(path)
	local f = io.open(path or M.UTMP, "rb")
	if not f then return {} end
	local out = {}
	while true do
		local data = f:read(M.SIZE)
		if not data or #data < M.SIZE then break end
		out[#out + 1] = M.unpack(data)
	end
	f:close()
	return out
end

-- The sessions somebody is logged into right now
function M.users(path)
	local out = {}
	for _, rec in ipairs(M.read(path)) do
		if rec.type == M.USER_PROCESS and rec.user ~= "" then
			out[#out + 1] = rec
		end
	end
	return out
end

return M
