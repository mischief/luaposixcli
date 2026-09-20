#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
-- gzip, gunzip and zcat. Which one it is comes from argv[0].
local gzip = require("luaposixcli.zlib.gzip")
local stat = require("posix.sys.stat")
local unistd = require("posix.unistd")
local utime = require("posix.utime")
local util = require("luaposixcli.util")

local prog = util.prog

local decompress = (prog == "gunzip" or prog == "zcat")
local to_stdout = (prog == "zcat")
local force, keep, test_only, verbose, no_name = false, false, false, false, false
local level = 6
local files = {}
local status = 0

local function warn(msg)
	util.warn(msg)
	if status < 1 then status = 1 end
end

local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "--" then
		for j = i + 1, #arg do files[#files + 1] = arg[j] end
		break
	elseif a:sub(1, 1) == "-" and #a > 1 then
		for c in a:sub(2):gmatch(".") do
			if c == "c" then to_stdout = true
			elseif c == "d" then decompress = true
			elseif c == "f" then force = true
			elseif c == "k" then keep = true
			elseif c == "n" then no_name = true
			elseif c == "t" then test_only = true; decompress = true
			elseif c == "v" then verbose = true
			elseif c:match("%d") then level = tonumber(c)
			else
				unistd.write(2, "usage: " .. prog .. " [-cdfkntv] [-1..-9] [file...]\n")
				os.exit(2)
			end
		end
	else
		files[#files + 1] = a
	end
	i = i + 1
end

local function write_file(path, data, mode, mtime)
	local f, err = io.open(path, "wb")
	if not f then return nil, err end
	f:write(data)
	f:close()
	if mode then stat.chmod(path, mode & tonumber("7777", 8)) end
	if mtime then utime.utime(path, mtime, mtime) end
	return true
end

local function exists(path)
	return stat.stat(path) ~= nil
end

-- Name of the output file, or nil when the input name is unusable
local function target(path)
	if decompress then
		local base = path:match("^(.*)%.gz$") or path:match("^(.*)%.z$")
			or path:match("^(.*)%.Z$")
		if base then return base end
		local tgz = path:match("^(.*)%.tgz$")
		if tgz then return tgz .. ".tar" end
		return nil, "unknown suffix"
	end
	if path:match("%.gz$") then return nil, "already has .gz suffix" end
	return path .. ".gz"
end

local function report(inname, insize, outsize)
	if not verbose then return end
	local ratio = insize > 0 and (100.0 - outsize * 100.0 / insize) or 0.0
	unistd.write(2, string.format("%s:\t%.1f%% (%d => %d bytes)\n",
		inname, ratio, insize, outsize))
end

local function one(path)
	local data, err = util.slurp(path)
	if not data then
		warn(err or ((path or "stdin") .. ": cannot read"))
		return
	end

	local out
	if decompress then
		out, err = gzip.decompress(data)
		if not out then
			warn((path or "stdin") .. ": " .. err)
			return
		end
		if test_only then return end
	else
		local opts = { level = level }
		if path and not no_name and not to_stdout then
			opts.name = path:match("([^/]+)$")
			local st = stat.stat(path)
			if st then opts.mtime = st.st_mtime end
		end
		out = gzip.compress(data, opts)
	end

	if path == nil or to_stdout then
		unistd.write(1, out)
		report(path or "stdin", #data, #out)
		return
	end

	local outpath, terr = target(path)
	if not outpath then
		warn(path .. ": " .. terr)
		return
	end
	if exists(outpath) and not force then
		warn(outpath .. " already exists; not overwritten")
		return
	end
	local st = stat.stat(path)
	local ok, werr = write_file(outpath, out, st and st.st_mode, st and st.st_mtime)
	if not ok then
		warn(outpath .. ": " .. (werr or "cannot write"))
		return
	end
	report(path, #data, #out)
	if not keep then unistd.unlink(path) end
end

if #files == 0 then
	one(nil)
else
	for _, path in ipairs(files) do one(path) end
end

os.exit(status)
