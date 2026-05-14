-- SPDX-License-Identifier: ISC
-- tar/format.lua - ustar tar archive encoder/decoder
local unistd = require("posix.unistd")
local stat = require("posix.sys.stat")

local M = {}

local BLOCK = 512

-- ustar header field offsets and sizes (0-indexed in spec, 1-indexed here)
local FIELDS = {
	name     = { 1,   100 },
	mode     = { 101, 8 },
	uid      = { 109, 8 },
	gid      = { 117, 8 },
	size     = { 125, 12 },
	mtime    = { 137, 12 },
	chksum   = { 149, 8 },
	typeflag = { 157, 1 },
	linkname = { 158, 100 },
	magic    = { 258, 6 },
	version  = { 264, 2 },
	uname    = { 266, 32 },
	gname    = { 298, 32 },
	devmajor = { 330, 8 },
	devminor = { 338, 8 },
	prefix   = { 346, 155 },
}

-- Pack a string into a fixed-width field (null-terminated if shorter)
local function pack_str(s, width)
	if #s >= width then return s:sub(1, width) end
	return s .. string.rep("\0", width - #s)
end

-- Pack a number as zero-padded octal with trailing null
local function pack_oct(n, width)
	local s = string.format("%0" .. (width - 1) .. "o", n)
	return s:sub(-(width - 1)) .. "\0"
end

-- Extract a null-terminated string from a block
local function unpack_str(block, offset, len)
	local s = block:sub(offset, offset + len - 1)
	local nul = s:find("\0")
	if nul then s = s:sub(1, nul - 1) end
	return s
end

-- Extract an octal number from a block
local function unpack_oct(block, offset, len)
	local s = unpack_str(block, offset, len)
	if s == "" then return 0 end
	return tonumber(s, 8) or 0
end

-- Compute header checksum (sum of unsigned bytes, with chksum field as spaces)
local function compute_checksum(header)
	local sum = 0
	for i = 1, BLOCK do
		local b = header:byte(i)
		-- chksum field is bytes 149-156, treat as spaces
		if i >= 149 and i <= 156 then
			sum = sum + 32
		else
			sum = sum + b
		end
	end
	return sum
end

-- Encode a tar header from a table of fields.
-- hdr: { name, mode, uid, gid, size, mtime, typeflag, linkname, uname, gname }
function M.encode_header(hdr)
	local buf = string.rep("\0", BLOCK)
	local parts = {}
	for i = 1, BLOCK do parts[i] = "\0" end

	local function set(field, value)
		local off, len = FIELDS[field][1], FIELDS[field][2]
		for i = 1, len do
			parts[off + i - 1] = value:sub(i, i) ~= "" and value:sub(i, i) or "\0"
		end
	end

	-- Split long names into prefix + name
	local name = hdr.name or ""
	local prefix = ""
	if #name > 100 then
		-- Find a / to split at, with prefix <= 155 and name <= 100
		local split = #name - 100
		local slash = name:find("/", split)
		if slash and slash <= 155 then
			prefix = name:sub(1, slash - 1)
			name = name:sub(slash + 1)
		else
			name = name:sub(1, 100) -- truncate
		end
	end

	set("name", pack_str(name, 100))
	set("mode", pack_oct(hdr.mode or 0, 8))
	set("uid", pack_oct(hdr.uid or 0, 8))
	set("gid", pack_oct(hdr.gid or 0, 8))
	set("size", pack_oct(hdr.size or 0, 12))
	set("mtime", pack_oct(hdr.mtime or 0, 12))
	set("chksum", "        ") -- spaces for checksum calculation
	set("typeflag", (hdr.typeflag or "0"):sub(1, 1))
	set("linkname", pack_str(hdr.linkname or "", 100))
	set("magic", "ustar\0")
	set("version", "00")
	set("uname", pack_str(hdr.uname or "", 32))
	set("gname", pack_str(hdr.gname or "", 32))
	set("devmajor", pack_oct(hdr.devmajor or 0, 8))
	set("devminor", pack_oct(hdr.devminor or 0, 8))
	set("prefix", pack_str(prefix, 155))

	-- Compute and set checksum
	buf = table.concat(parts)
	local cksum = compute_checksum(buf)
	local cksum_str = string.format("%06o\0 ", cksum)
	buf = buf:sub(1, 148) .. cksum_str .. buf:sub(157)

	return buf
end

-- Decode a 512-byte block into a header table. Returns nil if block is all zeros (EOF).
function M.decode_header(block)
	if #block < BLOCK then return nil end
	-- Check for EOF (all zeros)
	if block == string.rep("\0", BLOCK) then return nil end

	local hdr = {}
	hdr.name = unpack_str(block, FIELDS.name[1], FIELDS.name[2])
	hdr.mode = unpack_oct(block, FIELDS.mode[1], FIELDS.mode[2])
	hdr.uid = unpack_oct(block, FIELDS.uid[1], FIELDS.uid[2])
	hdr.gid = unpack_oct(block, FIELDS.gid[1], FIELDS.gid[2])
	hdr.size = unpack_oct(block, FIELDS.size[1], FIELDS.size[2])
	hdr.mtime = unpack_oct(block, FIELDS.mtime[1], FIELDS.mtime[2])
	hdr.chksum = unpack_oct(block, FIELDS.chksum[1], FIELDS.chksum[2])
	hdr.typeflag = unpack_str(block, FIELDS.typeflag[1], FIELDS.typeflag[2])
	hdr.linkname = unpack_str(block, FIELDS.linkname[1], FIELDS.linkname[2])
	hdr.magic = unpack_str(block, FIELDS.magic[1], FIELDS.magic[2])
	hdr.version = unpack_str(block, FIELDS.version[1], FIELDS.version[2])
	hdr.uname = unpack_str(block, FIELDS.uname[1], FIELDS.uname[2])
	hdr.gname = unpack_str(block, FIELDS.gname[1], FIELDS.gname[2])
	hdr.devmajor = unpack_oct(block, FIELDS.devmajor[1], FIELDS.devmajor[2])
	hdr.devminor = unpack_oct(block, FIELDS.devminor[1], FIELDS.devminor[2])
	hdr.prefix = unpack_str(block, FIELDS.prefix[1], FIELDS.prefix[2])

	-- Reconstruct full name from prefix
	if hdr.prefix ~= "" then
		hdr.name = hdr.prefix .. "/" .. hdr.name
	end

	-- Verify checksum
	local expected = compute_checksum(block)
	if hdr.chksum ~= expected then
		return nil, "checksum mismatch"
	end

	-- Normalize typeflag
	if hdr.typeflag == "" or hdr.typeflag == "\0" then hdr.typeflag = "0" end

	return hdr
end

-- Pad data to a 512-byte block boundary
function M.pad_data(data)
	local rem = #data % BLOCK
	if rem == 0 then return data end
	return data .. string.rep("\0", BLOCK - rem)
end

-- Return the number of data blocks for a given file size
function M.data_blocks(size)
	return math.ceil(size / BLOCK)
end

-- EOF marker: two zero blocks
function M.eof_marker()
	return string.rep("\0", BLOCK * 2)
end

-- Read one entry (header + data) from a file descriptor.
-- Returns header, data (string) or nil on EOF.
function M.read_entry(fd)
	local block = unistd.read(fd, BLOCK)
	if not block or #block < BLOCK then return nil end

	local hdr, err = M.decode_header(block)
	if not hdr then return nil, err end

	local data = ""
	if hdr.size > 0 then
		local to_read = M.data_blocks(hdr.size) * BLOCK
		data = unistd.read(fd, to_read) or ""
		data = data:sub(1, hdr.size) -- trim padding
	end

	return hdr, data
end

-- Write one entry (header + padded data) to a file descriptor.
function M.write_entry(fd, hdr, data)
	local header_block = M.encode_header(hdr)
	unistd.write(fd, header_block)
	if data and #data > 0 then
		unistd.write(fd, M.pad_data(data))
	end
end

return M
