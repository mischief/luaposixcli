-- SPDX-License-Identifier: ISC
-- bc/bignum.lua - arbitrary precision decimal arithmetic
-- Uses base-10000 limbs stored least-significant first.
local M = {}
M.__index = M

local BASE = 10000
local DIGS = 4 -- digits per limb

-- Create a bignum from an integer or string
function M.new(v)
	local self = setmetatable({ limbs = {}, neg = false, scale = 0 }, M)
	if type(v) == "number" then
		if v < 0 then self.neg = true; v = -v end
		v = math.floor(v)
		if v == 0 then self.limbs[1] = 0; return self end
		while v > 0 do
			self.limbs[#self.limbs + 1] = v % BASE
			v = math.floor(v / BASE)
		end
	elseif type(v) == "string" then
		v = v:match("^%s*(.-)%s*$")
		if v:sub(1, 1) == "-" then self.neg = true; v = v:sub(2) end
		-- Split on decimal point
		local int_part, frac_part = v:match("^(%d*)(%.?%d*)$")
		if not int_part then self.limbs[1] = 0; return self end
		frac_part = frac_part:gsub("^%.", "")
		self.scale = #frac_part
		-- Combine into one digit string
		local digits = int_part .. frac_part
		digits = digits:gsub("^0+", "")
		if digits == "" then digits = "0" end
		-- Parse into limbs (least significant first)
		local i = #digits
		while i >= 1 do
			local start = math.max(1, i - DIGS + 1)
			local chunk = digits:sub(start, i)
			self.limbs[#self.limbs + 1] = tonumber(chunk)
			i = start - 1
		end
	end
	if #self.limbs == 0 then self.limbs[1] = 0 end
	self:trim()
	return self
end

-- Remove leading zero limbs
function M:trim()
	while #self.limbs > 1 and self.limbs[#self.limbs] == 0 do
		self.limbs[#self.limbs] = nil
	end
	if #self.limbs == 1 and self.limbs[1] == 0 then self.neg = false end
end

-- Check if zero
function M:is_zero()
	return #self.limbs == 1 and self.limbs[1] == 0
end

-- Compare absolute values. Returns -1, 0, or 1
function M.cmp_abs(a, b)
	if #a.limbs ~= #b.limbs then return #a.limbs < #b.limbs and -1 or 1 end
	for i = #a.limbs, 1, -1 do
		if a.limbs[i] ~= b.limbs[i] then
			return a.limbs[i] < b.limbs[i] and -1 or 1
		end
	end
	return 0
end

-- Add absolute values (ignoring sign/scale)
local function add_abs(a, b)
	local r = { limbs = {}, neg = false, scale = 0 }
	setmetatable(r, M)
	local carry = 0
	local n = math.max(#a.limbs, #b.limbs)
	for i = 1, n do
		local s = (a.limbs[i] or 0) + (b.limbs[i] or 0) + carry
		r.limbs[i] = s % BASE
		carry = math.floor(s / BASE)
	end
	if carry > 0 then r.limbs[n + 1] = carry end
	return r
end

-- Subtract absolute values (a >= b assumed)
local function sub_abs(a, b)
	local r = { limbs = {}, neg = false, scale = 0 }
	setmetatable(r, M)
	local borrow = 0
	for i = 1, #a.limbs do
		local s = a.limbs[i] - (b.limbs[i] or 0) - borrow
		if s < 0 then s = s + BASE; borrow = 1 else borrow = 0 end
		r.limbs[i] = s
	end
	r:trim()
	return r
end

-- Align scales: pad the one with fewer fractional digits
local function align(a, b)
	if a.scale == b.scale then return a, b end
	local diff
	if a.scale < b.scale then
		diff = b.scale - a.scale
		a = M.copy(a)
		-- Multiply a by 10^diff
		a = M.mul_pow10(a, diff)
		a.scale = b.scale
	else
		diff = a.scale - b.scale
		b = M.copy(b)
		b = M.mul_pow10(b, diff)
		b.scale = a.scale
	end
	return a, b
end

-- Multiply by 10^n (shift digits left)
function M.mul_pow10(a, n)
	if n == 0 then return a end
	local s = M.to_digit_string(a)
	s = s .. string.rep("0", n)
	local r = M.new(s)
	r.neg = a.neg
	r.scale = a.scale
	return r
end

-- Deep copy
function M.copy(a)
	local r = { limbs = {}, neg = a.neg, scale = a.scale }
	for i, v in ipairs(a.limbs) do r.limbs[i] = v end
	return setmetatable(r, M)
end

-- Convert to raw digit string (no decimal point, no sign)
function M.to_digit_string(a)
	local parts = {}
	for i = #a.limbs, 1, -1 do
		if i == #a.limbs then
			parts[#parts + 1] = tostring(a.limbs[i])
		else
			parts[#parts + 1] = string.format("%0" .. DIGS .. "d", a.limbs[i])
		end
	end
	local s = table.concat(parts)
	if s == "" then s = "0" end
	return s
end

-- Addition
function M.add(a, b)
	a, b = align(a, b)
	local r
	if a.neg == b.neg then
		r = add_abs(a, b)
		r.neg = a.neg
	else
		local cmp = M.cmp_abs(a, b)
		if cmp >= 0 then
			r = sub_abs(a, b)
			r.neg = a.neg
		else
			r = sub_abs(b, a)
			r.neg = b.neg
		end
	end
	r.scale = a.scale
	r:trim()
	return r
end

-- Subtraction
function M.sub(a, b)
	local nb = M.copy(b)
	nb.neg = not b.neg
	return M.add(a, nb)
end

-- Multiplication
function M.mul(a, b)
	local r = { limbs = {}, neg = a.neg ~= b.neg, scale = a.scale + b.scale }
	setmetatable(r, M)
	local n = #a.limbs + #b.limbs
	for i = 1, n do r.limbs[i] = 0 end
	for i = 1, #a.limbs do
		local carry = 0
		for j = 1, #b.limbs do
			local p = a.limbs[i] * b.limbs[j] + r.limbs[i + j - 1] + carry
			r.limbs[i + j - 1] = p % BASE
			carry = math.floor(p / BASE)
		end
		if carry > 0 then r.limbs[i + #b.limbs] = r.limbs[i + #b.limbs] + carry end
	end
	r:trim()
	return r
end

-- Division with specified scale (decimal places in result)
function M.div(a, b, scale)
	scale = scale or math.max(a.scale, b.scale, 0)
	if b:is_zero() then error("divide by zero") end
	-- Scale numerator to get enough precision
	local total_scale = scale + b.scale
	local num = M.copy(a)
	num.neg = false
	num.scale = 0
	if total_scale > a.scale then
		num = M.mul_pow10(num, total_scale - a.scale)
	end
	local den = M.copy(b)
	den.neg = false
	den.scale = 0

	-- Long division
	local q = M.divmod_abs(num, den)
	q.neg = a.neg ~= b.neg
	q.scale = scale
	q:trim()
	return q
end

-- Integer division and modulus of absolute values
function M.divmod_abs(a, b)
	if b:is_zero() then error("divide by zero") end
	if M.cmp_abs(a, b) < 0 then return M.new(0) end

	-- Simple long division using digit string
	local a_str = M.to_digit_string(a)
	local result = {}
	local rem = M.new(0)
	for i = 1, #a_str do
		-- rem = rem * 10 + digit
		rem = add_abs(M.mul_small(rem, 10), M.new(tonumber(a_str:sub(i, i))))
		-- Find how many times b fits
		local count = 0
		while M.cmp_abs(rem, b) >= 0 do
			rem = sub_abs(rem, b)
			count = count + 1
		end
		result[#result + 1] = tostring(count)
	end
	local q = M.new(table.concat(result))
	return q
end

-- Multiply by a small integer (0-9999)
function M.mul_small(a, n)
	local r = { limbs = {}, neg = a.neg, scale = a.scale }
	setmetatable(r, M)
	local carry = 0
	for i = 1, #a.limbs do
		local p = a.limbs[i] * n + carry
		r.limbs[i] = p % BASE
		carry = math.floor(p / BASE)
	end
	while carry > 0 do
		r.limbs[#r.limbs + 1] = carry % BASE
		carry = math.floor(carry / BASE)
	end
	if #r.limbs == 0 then r.limbs[1] = 0 end
	r:trim()
	return r
end

-- Modulus
function M.mod(a, b, scale)
	local q = M.div(a, b, 0)
	q.scale = 0
	return M.sub(a, M.mul(q, b))
end

-- Exponentiation (integer exponent only)
function M.pow(base, exp)
	local e = tonumber(M.to_string(exp))
	if not e then e = 0 end
	e = math.floor(e)
	if e < 0 then return M.new(0) end -- bc truncates negative exp to 0
	if e == 0 then return M.new(1) end
	local result = M.new(1)
	local b = M.copy(base)
	b.scale = 0
	while e > 0 do
		if e % 2 == 1 then result = M.mul(result, b) end
		b = M.mul(b, b)
		e = math.floor(e / 2)
	end
	result.scale = base.scale * tonumber(M.to_string(exp))
	return result
end

-- Convert to display string with decimal point
function M.to_string(a)
	local s = M.to_digit_string(a)
	if a.scale > 0 then
		while #s <= a.scale do s = "0" .. s end
		s = s:sub(1, #s - a.scale) .. "." .. s:sub(#s - a.scale + 1)
		-- Remove trailing zeros after decimal (bc doesn't, but keep for now)
	end
	if a.neg and s ~= "0" then s = "-" .. s end
	return s
end

-- Compare: returns -1, 0, 1
function M.compare(a, b)
	a, b = align(a, b)
	if a.neg and not b.neg then return -1 end
	if not a.neg and b.neg then return 1 end
	local cmp = M.cmp_abs(a, b)
	if a.neg then cmp = -cmp end
	return cmp
end

-- Square root (Newton's method)
function M.sqrt(a, scale)
	scale = scale or 0
	if a.neg then error("square root of negative number") end
	if a:is_zero() then return M.new(0) end
	-- Work with extra precision
	local work_scale = scale + 2
	local two = M.new(2)
	-- Initial guess: half the digits
	local x = M.new(1)
	for _ = 1, 50 do
		local xn = M.div(M.add(x, M.div(a, x, work_scale)), two, work_scale)
		if M.compare(x, xn) == 0 then break end
		x = xn
	end
	x.scale = scale
	-- Truncate to requested scale
	local s = M.to_digit_string(x)
	if #s > #M.to_digit_string(a) + scale then
		s = s:sub(1, #M.to_digit_string(a) + scale)
		x = M.new(s)
		x.scale = scale
	end
	return x
end

return M
