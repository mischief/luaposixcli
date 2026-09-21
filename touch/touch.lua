#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local fcntl = require("posix.fcntl")
local utime = require("posix.utime")
local stat = require("posix.sys.stat")

local no_create = false
local set_access, set_modify = false, false
local reference, timestamp = nil, nil
local optind = 1

local function usage()
	unistd.write(2, "usage: touch [-acm] [-r file] [-t time] file...\n")
	os.exit(2)
end

for opt, optarg, oi in unistd.getopt(arg, "acmr:t:") do
	if opt == "a" then set_access = true
	elseif opt == "m" then set_modify = true
	elseif opt == "c" then no_create = true
	elseif opt == "r" then reference = optarg
	elseif opt == "t" then timestamp = optarg
	else usage() end
	optind = oi
end
if arg[optind] == "--" then optind = optind + 1 end

local files = {}
for i = optind, #arg do files[#files + 1] = arg[i] end
if #files == 0 then usage() end

-- neither -a nor -m means both
if not set_access and not set_modify then
	set_access, set_modify = true, true
end

-- -t is [[CC]YY]MMDDhhmm[.SS]
local function parse_time(text)
	local body, seconds = text:match("^(%d+)%.?(%d*)$")
	if not body or (#body ~= 8 and #body ~= 10 and #body ~= 12) then
		unistd.write(2, "touch: " .. text .. ": bad time\n")
		os.exit(2)
	end
	local now = os.date("*t")
	local year = now.year
	if #body == 12 then
		year = tonumber(body:sub(1, 4))
		body = body:sub(5)
	elseif #body == 10 then
		local yy = tonumber(body:sub(1, 2))
		year = yy < 69 and (2000 + yy) or (1900 + yy)
		body = body:sub(3)
	end
	return os.time({
		year = year,
		month = tonumber(body:sub(1, 2)),
		day = tonumber(body:sub(3, 4)),
		hour = tonumber(body:sub(5, 6)),
		min = tonumber(body:sub(7, 8)),
		sec = tonumber(seconds) or 0,
		-- isdst left out on purpose: the time given is local, and only
		-- the C library knows whether that date was in daylight time
	})
end

local when = nil
if reference then
	local st = stat.stat(reference)
	if not st then
		unistd.write(2, "touch: " .. reference .. ": No such file or directory\n")
		os.exit(1)
	end
	when = { atime = st.st_atime, mtime = st.st_mtime }
elseif timestamp then
	local t = parse_time(timestamp)
	when = { atime = t, mtime = t }
end

local status = 0
for _, path in ipairs(files) do
	local st = stat.stat(path)
	if not st then
		if no_create then goto continue end
		local fd = fcntl.open(path, fcntl.O_WRONLY | fcntl.O_CREAT, tonumber("666", 8))
		if not fd then
			unistd.write(2, "touch: " .. path .. ": cannot create\n")
			status = 1
			goto continue
		end
		unistd.close(fd)
		st = stat.stat(path)
	end

	-- the time not being set keeps what the file has
	local now = os.time()
	local atime = (when and when.atime) or now
	local mtime = (when and when.mtime) or now
	if not set_access and st then atime = st.st_atime end
	if not set_modify and st then mtime = st.st_mtime end
	local ok, err = utime.utime(path, mtime, atime)
	if not ok then
		unistd.write(2, "touch: " .. (err or path .. ": cannot set the time") .. "\n")
		status = 1
	end
	::continue::
end
os.exit(status)
