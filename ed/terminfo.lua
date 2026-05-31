-- SPDX-License-Identifier: ISC
-- ed/terminfo.lua - terminal control using ANSI/VT100 escape sequences
local unistd = require("posix.unistd")
local termio = require("posix.termio")

local M = {}

local ESC = "\027"
local CSI = ESC .. "["

-- Create a terminal instance
function M.new()
	local self = {
		rows = 24,
		cols = 80,
		orig_termios = nil,
	}
	-- Try to detect size
	local r = os.getenv("LINES")
	local c = os.getenv("COLUMNS")
	if r then self.rows = tonumber(r) end
	if c then self.cols = tonumber(c) end
	return setmetatable(self, { __index = M })
end

-- Enter raw mode
function M:raw()
	self.orig_termios = termio.tcgetattr(0)
	if not self.orig_termios then return end
	local raw = {}
	for k, v in pairs(self.orig_termios) do raw[k] = v end
	raw.lflag = raw.lflag & ~(termio.ICANON | termio.ECHO | termio.ISIG)
	raw.iflag = raw.iflag & ~(termio.IXON | termio.ICRNL)
	raw.oflag = raw.oflag & ~(termio.OPOST)
	raw.cc = raw.cc or {}
	raw.cc[termio.VMIN] = 1
	raw.cc[termio.VTIME] = 0
	termio.tcsetattr(0, termio.TCSANOW, raw)
end

-- Restore terminal
function M:restore()
	if self.orig_termios then
		termio.tcsetattr(0, termio.TCSANOW, self.orig_termios)
	end
end

-- Output helpers
function M:write(s)
	unistd.write(1, s)
end

-- Cursor movement
function M:move(row, col)
	self:write(CSI .. row .. ";" .. col .. "H")
end

function M:up(n)
	self:write(CSI .. (n or 1) .. "A")
end

function M:down(n)
	self:write(CSI .. (n or 1) .. "B")
end

function M:right(n)
	self:write(CSI .. (n or 1) .. "C")
end

function M:left(n)
	self:write(CSI .. (n or 1) .. "D")
end

function M:home()
	self:write(CSI .. "H")
end

function M:col1()
	self:write("\r")
end

-- Clearing
function M:clear()
	self:write(CSI .. "2J" .. CSI .. "H")
end

function M:clear_line()
	self:write(CSI .. "2K")
end

function M:clear_eol()
	self:write(CSI .. "K")
end

function M:clear_eos()
	self:write(CSI .. "J")
end

-- Cursor visibility
function M:hide_cursor()
	self:write(CSI .. "?25l")
end

function M:show_cursor()
	self:write(CSI .. "?25h")
end

-- Attributes
function M:reset()
	self:write(CSI .. "0m")
end

function M:bold()
	self:write(CSI .. "1m")
end

function M:reverse()
	self:write(CSI .. "7m")
end

-- Scrolling region
function M:scroll_region(top, bottom)
	self:write(CSI .. top .. ";" .. bottom .. "r")
end

function M:scroll_reset()
	self:write(CSI .. "r")
end

-- Read a single keypress (handles escape sequences)
-- Returns: string key name or character
function M:readkey()
	local c = unistd.read(0, 1)
	if not c or c == "" then return nil end

	if c ~= ESC then return c end

	-- Escape: peek for sequence with a short timeout
	local poll = require("posix.poll")
	local ready = poll.poll({ [0] = { events = { IN = true } } }, 50)
	if not ready or ready == 0 then
		return "escape"
	end

	local c2 = unistd.read(0, 1)
	if not c2 or c2 == "" then return "escape" end

	if c2 == "[" then
		local c3 = unistd.read(0, 1)
		if not c3 then return "escape" end
		if c3 == "A" then return "up"
		elseif c3 == "B" then return "down"
		elseif c3 == "C" then return "right"
		elseif c3 == "D" then return "left"
		elseif c3 == "H" then return "home"
		elseif c3 == "F" then return "end"
		elseif c3 >= "0" and c3 <= "9" then
			-- Extended: \e[N~ sequences
			local num = c3
			local c4 = unistd.read(0, 1)
			while c4 and c4 >= "0" and c4 <= "9" do
				num = num .. c4
				c4 = unistd.read(0, 1)
			end
			-- c4 should be '~'
			local n = tonumber(num)
			if n == 1 then return "home"
			elseif n == 3 then return "delete"
			elseif n == 4 then return "end"
			elseif n == 5 then return "pageup"
			elseif n == 6 then return "pagedown"
			else return "esc[" .. num .. "~" end
		else
			return "esc[" .. c3
		end
	elseif c2 == "O" then
		local c3 = unistd.read(0, 1)
		if c3 == "H" then return "home"
		elseif c3 == "F" then return "end"
		else return "escO" .. (c3 or "") end
	end

	return "esc" .. c2
end

-- Query terminal size using cursor position trick
function M:detect_size()
	-- Save cursor, move to 999,999, query position, restore
	self:write(CSI .. "s" .. CSI .. "999;999H" .. CSI .. "6n" .. CSI .. "u")
	-- Read response: \e[rows;colsR
	local buf = {}
	while true do
		local c = unistd.read(0, 1)
		if not c or c == "R" then break end
		buf[#buf + 1] = c
	end
	local resp = table.concat(buf)
	local r, c = resp:match("%[(%d+);(%d+)")
	if r and c then
		self.rows = tonumber(r)
		self.cols = tonumber(c)
	end
end

return M
