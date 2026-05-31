#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
-- vi - visual editor
local a = arg or { [0] = "vi" }
local src = a[0]:match("(.+/)") or "./"
local prefix = src .. "../"
package.path = prefix .. "?.lua;" .. prefix .. "share/lua/5.4/?.lua;" .. package.path
if not package.cpath:find("build") then
	package.cpath = prefix .. "build/?.so;" .. prefix .. "lib/lua/5.4/?.so;" .. package.cpath
end

local unistd = require("posix.unistd")
local buffer = require("ed.buffer")
local term = require("ed.terminfo").new()

-- Parse options
local readonly = false
local file = nil
local optind = 1
for opt, optarg, oi in unistd.getopt(a, "Rc:t:") do
	if opt == "R" then readonly = true
	elseif opt == "c" then -- initial command (TODO)
	elseif opt == "t" then -- tag (TODO)
	elseif opt == "?" then
		unistd.write(2, "usage: vi [-R] [-c command] [file ...]\n")
		os.exit(1)
	end
	optind = oi
end
if a[optind] then file = a[optind] end

-- Create buffer (ex mode for full command set)
local buf = buffer.new({ file = file, suppress = true, ex_mode = true })
if file then buf:load(file) end
if #buf.lines == 0 then buf.lines = { "" }; buf.cur = 1 end

-- Editor state
local top = 1 -- first visible line
local cx, cy = 1, 1 -- cursor col, row (1-indexed, relative to buffer line)
local mode = "normal" -- normal, insert, command
local cmd_buf = "" -- for : commands
local status_msg = ""
local insert_col = 1

-- Helpers
local function bufline()
	return top + cy - 1
end

local function clamp()
	if buf.cur < 1 then buf.cur = 1 end
	if buf.cur > #buf.lines then buf.cur = #buf.lines end
	-- Keep cursor in view
	if buf.cur < top then top = buf.cur end
	if buf.cur >= top + term.rows - 1 then top = buf.cur - term.rows + 2 end
	cy = buf.cur - top + 1
	-- Clamp cx
	local line = buf.lines[buf.cur] or ""
	if cx > #line then cx = math.max(1, #line) end
	if cx < 1 then cx = 1 end
end

local function draw()
	term:hide_cursor()
	term:move(1, 1)
	for i = 1, term.rows - 1 do
		local ln = top + i - 1
		term:clear_eol()
		if ln <= #buf.lines then
			local line = buf.lines[ln]
			if #line > term.cols then line = line:sub(1, term.cols) end
			term:write(line)
		else
			term:write("~")
		end
		if i < term.rows - 1 then term:write("\r\n") end
	end
	-- Status line
	term:write("\r\n")
	term:clear_eol()
	if mode == "command" then
		term:write(":" .. cmd_buf)
	elseif status_msg ~= "" then
		term:write(status_msg)
		status_msg = ""
	else
		local fn = buf.file or "[No Name]"
		local mod = buf.dirty and " [+]" or ""
		local pos = string.format("%d/%d", buf.cur, #buf.lines)
		term:write(fn .. mod .. "  " .. pos)
	end
	term:move(cy, cx)
	term:show_cursor()
end

local function set_status(msg)
	status_msg = msg
end

-- Normal mode key handling
local function normal_key(key)
	local line = buf.lines[buf.cur] or ""

	-- Movement
	if key == "h" or key == "left" then
		if cx > 1 then cx = cx - 1 end
	elseif key == "l" or key == "right" then
		if cx < #line then cx = cx + 1 end
	elseif key == "j" or key == "down" then
		if buf.cur < #buf.lines then buf.cur = buf.cur + 1; clamp() end
	elseif key == "k" or key == "up" then
		if buf.cur > 1 then buf.cur = buf.cur - 1; clamp() end
	elseif key == "0" or key == "home" then
		cx = 1
	elseif key == "$" or key == "end" then
		cx = math.max(1, #line)
	elseif key == "^" then
		cx = (line:find("%S") or 1)
	elseif key == "w" then
		-- Next word
		local pos = line:find("%s", cx)
		if pos then
			pos = line:find("%S", pos)
			if pos then cx = pos else cx = #line end
		else
			cx = #line
		end
	elseif key == "b" then
		-- Previous word
		if cx > 1 then
			local sub = line:sub(1, cx - 1)
			local pos = sub:find("%S[%s]*$")
			if pos then cx = pos else cx = 1 end
		end
	elseif key == "G" then
		buf.cur = #buf.lines; clamp()
	elseif key == "g" then
		-- gg = go to top (simplified: single g goes to top)
		buf.cur = 1; clamp()
	elseif key == "pagedown" or key == "\006" then -- Ctrl-F
		buf.cur = math.min(#buf.lines, buf.cur + term.rows - 2)
		top = math.min(#buf.lines, top + term.rows - 2)
		clamp()
	elseif key == "pageup" or key == "\002" then -- Ctrl-B
		buf.cur = math.max(1, buf.cur - term.rows + 2)
		top = math.max(1, top - term.rows + 2)
		clamp()

	-- Editing
	elseif key == "i" then
		mode = "insert"; insert_col = cx
	elseif key == "a" then
		cx = math.min(#line + 1, cx + 1)
		mode = "insert"; insert_col = cx
	elseif key == "A" then
		cx = #line + 1
		mode = "insert"; insert_col = cx
	elseif key == "I" then
		cx = (line:find("%S") or 1)
		mode = "insert"; insert_col = cx
	elseif key == "o" then
		table.insert(buf.lines, buf.cur + 1, "")
		buf.cur = buf.cur + 1; cx = 1; buf.dirty = true
		clamp(); mode = "insert"; insert_col = 1
	elseif key == "O" then
		table.insert(buf.lines, buf.cur, "")
		cx = 1; buf.dirty = true
		clamp(); mode = "insert"; insert_col = 1
	elseif key == "x" then
		if #line > 0 then
			buf.lines[buf.cur] = line:sub(1, cx - 1) .. line:sub(cx + 1)
			buf.dirty = true
			if cx > #buf.lines[buf.cur] and cx > 1 then cx = cx - 1 end
		end
	elseif key == "dd" or key == "D" then
		-- dd handled via pending, D deletes to end
		if key == "D" then
			buf.lines[buf.cur] = line:sub(1, cx - 1)
			buf.dirty = true
		end
	elseif key == "d" then
		-- Wait for second key (simplified: only dd)
		local k2 = term:readkey()
		if k2 == "d" then
			buf:delete(buf.cur, buf.cur)
			if #buf.lines == 0 then buf.lines = { "" }; buf.cur = 1 end
			clamp()
		end
	elseif key == "J" then
		if buf.cur < #buf.lines then
			buf.lines[buf.cur] = buf.lines[buf.cur] .. " " .. buf.lines[buf.cur + 1]
			table.remove(buf.lines, buf.cur + 1)
			buf.dirty = true
		end
	elseif key == "u" then
		set_status("undo not implemented")
	elseif key == "r" then
		local ch = term:readkey()
		if ch and #ch == 1 then
			buf.lines[buf.cur] = line:sub(1, cx - 1) .. ch .. line:sub(cx + 1)
			buf.dirty = true
		end

	-- Search
	elseif key == "/" then
		mode = "command"; cmd_buf = "/"
	elseif key == "?" then
		mode = "command"; cmd_buf = "?"
	elseif key == "n" then
		set_status("search repeat not implemented")

	-- Command mode
	elseif key == ":" then
		mode = "command"; cmd_buf = ""
	elseif key == "Z" then
		local k2 = term:readkey()
		if k2 == "Z" then
			if buf.file then buf:write() end
			return false
		elseif k2 == "Q" then
			return false
		end
	end
	return true
end

-- Insert mode key handling
local function insert_key(key)
	local line = buf.lines[buf.cur] or ""

	if key == "escape" then
		mode = "normal"
		if cx > 1 then cx = cx - 1 end
		return true
	elseif key == "\127" or key == "\008" then -- backspace
		if cx > 1 then
			buf.lines[buf.cur] = line:sub(1, cx - 2) .. line:sub(cx)
			cx = cx - 1; buf.dirty = true
		elseif buf.cur > 1 then
			-- Join with previous line
			cx = #buf.lines[buf.cur - 1] + 1
			buf.lines[buf.cur - 1] = buf.lines[buf.cur - 1] .. line
			table.remove(buf.lines, buf.cur)
			buf.cur = buf.cur - 1; buf.dirty = true
			clamp()
		end
	elseif key == "\r" or key == "\n" then
		-- Split line
		local before = line:sub(1, cx - 1)
		local after = line:sub(cx)
		buf.lines[buf.cur] = before
		table.insert(buf.lines, buf.cur + 1, after)
		buf.cur = buf.cur + 1; cx = 1; buf.dirty = true
		clamp()
	elseif key == "left" then
		if cx > 1 then cx = cx - 1 end
	elseif key == "right" then
		if cx <= #line then cx = cx + 1 end
	elseif key == "up" then
		if buf.cur > 1 then buf.cur = buf.cur - 1; clamp() end
	elseif key == "down" then
		if buf.cur < #buf.lines then buf.cur = buf.cur + 1; clamp() end
	elseif #key == 1 and key:byte() >= 32 then
		buf.lines[buf.cur] = line:sub(1, cx - 1) .. key .. line:sub(cx)
		cx = cx + 1; buf.dirty = true
	end
	return true
end

-- Command mode key handling
local function command_key(key)
	if key == "escape" then
		mode = "normal"; cmd_buf = ""
	elseif key == "\r" or key == "\n" then
		mode = "normal"
		local cmd = cmd_buf
		cmd_buf = ""
		-- Handle ex commands
		if cmd == "q" or cmd == "q!" then
			if cmd == "q" and buf.dirty then
				set_status("No write since last change (use :q! to override)")
				return true
			end
			return false
		elseif cmd == "w" then
			local ok, result = buf:write()
			if ok then set_status('"' .. buf.file .. '" written, ' .. result .. " bytes")
			else set_status(result) end
		elseif cmd == "wq" or cmd == "x" then
			buf:write()
			return false
		elseif cmd:sub(1, 2) == "w " then
			local fn = cmd:sub(3)
			local ok, result = buf:write(fn)
			if ok then set_status('"' .. fn .. '" written, ' .. result .. " bytes")
			else set_status(result) end
		elseif cmd:sub(1, 1) == "/" then
			-- Forward search
			local pat = cmd:sub(2)
			if pat ~= "" then
				for i = buf.cur + 1, #buf.lines do
					if buf.lines[i]:find(pat) then
						buf.cur = i; clamp()
						local pos = buf.lines[i]:find(pat)
						if pos then cx = pos end
						return true
					end
				end
				for i = 1, buf.cur do
					if buf.lines[i]:find(pat) then
						buf.cur = i; clamp()
						local pos = buf.lines[i]:find(pat)
						if pos then cx = pos end
						return true
					end
				end
				set_status("Pattern not found: " .. pat)
			end
		elseif cmd:sub(1, 1) == "?" then
			-- Backward search
			local pat = cmd:sub(2)
			if pat ~= "" then
				for i = buf.cur - 1, 1, -1 do
					if buf.lines[i]:find(pat) then
						buf.cur = i; clamp()
						local pos = buf.lines[i]:find(pat)
						if pos then cx = pos end
						return true
					end
				end
				set_status("Pattern not found: " .. pat)
			end
		elseif tonumber(cmd) then
			buf.cur = tonumber(cmd); clamp()
		else
			-- Try as ex command
			local result = buf:exec(cmd)
			if result == nil then return false end
			clamp()
		end
	elseif key == "\127" or key == "\008" then
		cmd_buf = cmd_buf:sub(1, -2)
	elseif #key == 1 and key:byte() >= 32 then
		cmd_buf = cmd_buf .. key
	end
	return true
end

-- Main
term:raw()
if unistd.isatty(0) == 1 then
	term:detect_size()
end
buf.cur = 1
clamp()

local ok, err = pcall(function()
	while true do
		draw()
		local key = term:readkey()
		if not key then break end

		local cont
		if mode == "normal" then
			cont = normal_key(key)
		elseif mode == "insert" then
			cont = insert_key(key)
		elseif mode == "command" then
			cont = command_key(key)
		end
		if cont == false then break end
	end
end)

term:clear()
term:restore()
if not ok then
	io.stderr:write("vi: " .. tostring(err) .. "\n")
	os.exit(1)
end
