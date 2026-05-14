#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
-- bc/bc.lua - POSIX bc (arbitrary precision calculator language)
local src_dir = (arg[0]:match("(.+/)") or "./") .. "../"
package.path = src_dir .. "?.lua;" .. package.path

local bignum = require("bc.bignum")
local unistd = require("posix.unistd")

local scale = 0
local ibase = 10
local obase = 10
local vars = {}
local arrays = {}
local functions = {}
local last_val = bignum.new(0)
local BREAK = {}
local RETURN = {}
local math_lib = false

-- Parse -l option
local files = {}
for i = 1, #arg do
	if arg[i] == "-l" then math_lib = true
	else files[#files + 1] = arg[i] end
end
if math_lib then scale = 20 end

-- Tokenizer
local tokens, tpos

local function tokenize(src)
	local t = {}
	local i = 1
	local len = #src
	while i <= len do
		local c = src:sub(i, i)
		if c == " " or c == "\t" then i = i + 1
		elseif c == "\\" and src:sub(i + 1, i + 1) == "\n" then i = i + 2
		elseif c == "\n" then t[#t + 1] = { type = "NEWLINE" }; i = i + 1
		elseif c == "#" then while i <= len and src:sub(i, i) ~= "\n" do i = i + 1 end
		elseif c == "/" and src:sub(i + 1, i + 1) == "*" then
			i = i + 2
			while i < len and not (src:sub(i, i) == "*" and src:sub(i + 1, i + 1) == "/") do i = i + 1 end
			i = i + 2
		elseif c == '"' then
			i = i + 1; local j = i
			while j <= len and src:sub(j, j) ~= '"' do j = j + 1 end
			t[#t + 1] = { type = "STRING", val = src:sub(i, j - 1) }
			i = j + 1
		elseif c:match("[0-9A-F.]") then
			local j = i
			while j <= len and src:sub(j, j):match("[0-9A-F.]") do j = j + 1 end
			t[#t + 1] = { type = "NUMBER", val = src:sub(i, j - 1) }
			i = j
		elseif c:match("[a-z]") then
			local j = i
			while j <= len and src:sub(j, j):match("[a-z]") do j = j + 1 end
			local w = src:sub(i, j - 1)
			local kw = { define="Define", break_="Break", quit="Quit", length="Length",
				["return"]="Return", ["for"]="For", ["if"]="If", ["while"]="While",
				sqrt="Sqrt", scale="Scale", ibase="Ibase", obase="Obase", auto="Auto" }
			-- "break" is a Lua keyword so use break_
			if w == "break" then t[#t + 1] = { type = "Break" }
			elseif kw[w] then t[#t + 1] = { type = kw[w] }
			else t[#t + 1] = { type = "LETTER", val = w } end
			i = j
		elseif c == "+" then
			if src:sub(i + 1, i + 1) == "+" then t[#t + 1] = { type = "INCR_DECR", val = "++" }; i = i + 2
			elseif src:sub(i + 1, i + 1) == "=" then t[#t + 1] = { type = "ASSIGN_OP", val = "+=" }; i = i + 2
			else t[#t + 1] = { type = "+", val = "+" }; i = i + 1 end
		elseif c == "-" then
			if src:sub(i + 1, i + 1) == "-" then t[#t + 1] = { type = "INCR_DECR", val = "--" }; i = i + 2
			elseif src:sub(i + 1, i + 1) == "=" then t[#t + 1] = { type = "ASSIGN_OP", val = "-=" }; i = i + 2
			else t[#t + 1] = { type = "-", val = "-" }; i = i + 1 end
		elseif c == "*" then
			if src:sub(i + 1, i + 1) == "=" then t[#t + 1] = { type = "ASSIGN_OP", val = "*=" }; i = i + 2
			else t[#t + 1] = { type = "MUL_OP", val = "*" }; i = i + 1 end
		elseif c == "/" then
			if src:sub(i + 1, i + 1) == "=" then t[#t + 1] = { type = "ASSIGN_OP", val = "/=" }; i = i + 2
			else t[#t + 1] = { type = "MUL_OP", val = "/" }; i = i + 1 end
		elseif c == "%" then
			if src:sub(i + 1, i + 1) == "=" then t[#t + 1] = { type = "ASSIGN_OP", val = "%=" }; i = i + 2
			else t[#t + 1] = { type = "MUL_OP", val = "%" }; i = i + 1 end
		elseif c == "^" then
			if src:sub(i + 1, i + 1) == "=" then t[#t + 1] = { type = "ASSIGN_OP", val = "^=" }; i = i + 2
			else t[#t + 1] = { type = "^", val = "^" }; i = i + 1 end
		elseif c == "=" then
			if src:sub(i + 1, i + 1) == "=" then t[#t + 1] = { type = "REL_OP", val = "==" }; i = i + 2
			else t[#t + 1] = { type = "ASSIGN_OP", val = "=" }; i = i + 2 - 1 end
		elseif c == "!" and src:sub(i + 1, i + 1) == "=" then
			t[#t + 1] = { type = "REL_OP", val = "!=" }; i = i + 2
		elseif c == "<" then
			if src:sub(i + 1, i + 1) == "=" then t[#t + 1] = { type = "REL_OP", val = "<=" }; i = i + 2
			else t[#t + 1] = { type = "REL_OP", val = "<" }; i = i + 1 end
		elseif c == ">" then
			if src:sub(i + 1, i + 1) == "=" then t[#t + 1] = { type = "REL_OP", val = ">=" }; i = i + 2
			else t[#t + 1] = { type = "REL_OP", val = ">" }; i = i + 1 end
		else t[#t + 1] = { type = c, val = c }; i = i + 1 end
	end
	t[#t + 1] = { type = "EOF" }
	return t
end

local function peek() return tokens[tpos] end
local function advance() tpos = tpos + 1; return tokens[tpos - 1] end
local function at(typ) return tokens[tpos] and tokens[tpos].type == typ end
local function match(typ) if at(typ) then return advance() end end
local function skip_nl() while at("NEWLINE") or at(";") do advance() end end

-- Forward declarations
local parse_expr, parse_stmt, parse_stmt_list, exec_stmt

-- Get/set named expressions
local function get_named(name, idx, locals)
	if name == "scale" then return bignum.new(scale) end
	if name == "ibase" then return bignum.new(ibase) end
	if name == "obase" then return bignum.new(obase) end
	if locals and locals[name] ~= nil then
		if idx then return (locals[name] or {})[bignum.to_string(idx)] or bignum.new(0) end
		return locals[name]
	end
	if idx then return (arrays[name] or {})[bignum.to_string(idx)] or bignum.new(0) end
	return vars[name] or bignum.new(0)
end

local function set_named(name, val, idx, locals)
	if name == "scale" then scale = math.floor(tonumber(bignum.to_string(val)) or 0); return end
	if name == "ibase" then ibase = math.floor(tonumber(bignum.to_string(val)) or 10); return end
	if name == "obase" then obase = math.floor(tonumber(bignum.to_string(val)) or 10); return end
	if locals and locals[name] ~= nil then
		if idx then
			if type(locals[name]) ~= "table" then locals[name] = {} end
			locals[name][bignum.to_string(idx)] = val
		else locals[name] = val end
		return
	end
	if idx then
		if not arrays[name] then arrays[name] = {} end
		arrays[name][bignum.to_string(idx)] = val
	else vars[name] = val end
end

-- Parse a named_expression, returns {name, idx_expr} or nil
local function parse_named()
	if at("Scale") then advance(); return { name = "scale" } end
	if at("Ibase") then advance(); return { name = "ibase" } end
	if at("Obase") then advance(); return { name = "obase" } end
	if at("LETTER") then
		local t = peek()
		-- Check for array: LETTER [ expr ]
		if tokens[tpos + 1] and tokens[tpos + 1].type == "[" then
			advance(); advance() -- LETTER [
			local idx = parse_expr()
			match("]")
			return { name = t.val, idx = idx }
		end
		-- Check it's not a function call
		if tokens[tpos + 1] and tokens[tpos + 1].type == "(" then return nil end
		advance()
		return { name = t.val }
	end
	return nil
end

-- Parse expression (handles assignment at lowest precedence)
function parse_expr(locals)
	-- Try named_expression ASSIGN_OP expression
	local saved = tpos
	local named = parse_named()
	if named and at("ASSIGN_OP") then
		local op = advance().val
		local rhs = parse_expr(locals)
		return { type = "assign", named = named, op = op, rhs = rhs }
	end
	tpos = saved
	-- Try named_expression INCR_DECR (postfix)
	named = parse_named()
	if named and at("INCR_DECR") then
		local op = advance().val
		return { type = "postfix", named = named, op = op }
	end
	tpos = saved
	return parse_add(locals)
end

-- Precedence climbing
local function parse_primary(locals)
	-- INCR_DECR named_expression (prefix)
	if at("INCR_DECR") then
		local op = advance().val
		local named = parse_named()
		return { type = "prefix", named = named, op = op }
	end
	-- unary -
	if at("-") then
		advance()
		local e = parse_primary(locals)
		return { type = "neg", expr = e }
	end
	-- ( expression )
	if match("(") then
		local e = parse_expr(locals)
		match(")")
		return e
	end
	-- NUMBER
	if at("NUMBER") then return { type = "num", val = advance().val } end
	-- Builtins: length(e), sqrt(e), scale(e)
	if at("Length") then advance(); match("("); local e = parse_expr(locals); match(")"); return { type = "builtin", fn = "length", arg = e } end
	if at("Sqrt") then advance(); match("("); local e = parse_expr(locals); match(")"); return { type = "builtin", fn = "sqrt", arg = e } end
	if at("Scale") then
		if tokens[tpos + 1] and tokens[tpos + 1].type == "(" then
			advance(); match("("); local e = parse_expr(locals); match(")")
			return { type = "builtin", fn = "scale", arg = e }
		end
		advance(); return { type = "named", name = "scale" }
	end
	if at("Ibase") then advance(); return { type = "named", name = "ibase" } end
	if at("Obase") then advance(); return { type = "named", name = "obase" } end
	-- LETTER ( args ) - function call
	if at("LETTER") and tokens[tpos + 1] and tokens[tpos + 1].type == "(" then
		local name = advance().val; advance() -- skip (
		local args = {}
		if not at(")") then
			args[1] = parse_expr(locals)
			while match(",") do args[#args + 1] = parse_expr(locals) end
		end
		match(")")
		return { type = "call", name = name, args = args }
	end
	-- named_expression
	local saved = tpos
	local named = parse_named()
	if named then return { type = "named_ref", named = named } end
	tpos = saved
	return { type = "num", val = "0" }
end

local function parse_power(locals)
	local left = parse_primary(locals)
	while at("^") do advance(); left = { type = "binop", op = "^", left = left, right = parse_primary(locals) } end
	return left
end

local function parse_mul(locals)
	local left = parse_power(locals)
	while at("MUL_OP") do local op = advance().val; left = { type = "binop", op = op, left = left, right = parse_power(locals) } end
	return left
end

function parse_add(locals)
	local left = parse_mul(locals)
	while at("+") or at("-") do local op = advance().val; left = { type = "binop", op = op, left = left, right = parse_mul(locals) } end
	-- Handle relational operators as part of expression (extension, but common)
	if at("REL_OP") then
		local op = advance().val
		local right = parse_add(locals)
		return { type = "rel", op = op, left = left, right = right }
	end
	return left
end

local function parse_relexpr(locals)
	local left = parse_expr(locals)
	if at("REL_OP") then
		local op = advance().val
		local right = parse_expr(locals)
		return { type = "rel", op = op, left = left, right = right }
	end
	return left
end

-- Parse statement
function parse_stmt(locals)
	skip_nl()
	if at("EOF") or at("}") then return nil end
	if at("STRING") then return { type = "string", val = advance().val } end
	if at("Break") then advance(); return { type = "break" } end
	if at("Quit") then advance(); return { type = "quit" } end
	if at("Return") then
		advance()
		if match("(") then
			local e = at(")") and nil or parse_expr(locals)
			match(")")
			return { type = "return", expr = e }
		end
		return { type = "return" }
	end
	if at("If") then
		advance(); match("(")
		local cond = parse_relexpr(locals)
		match(")")
		local body = parse_stmt(locals)
		return { type = "if", cond = cond, body = body }
	end
	if at("While") then
		advance(); match("(")
		local cond = parse_relexpr(locals)
		match(")")
		local body = parse_stmt(locals)
		return { type = "while", cond = cond, body = body }
	end
	if at("For") then
		advance(); match("(")
		local init = parse_expr(locals); match(";")
		local cond = parse_relexpr(locals); match(";")
		local step = parse_expr(locals); match(")")
		local body = parse_stmt(locals)
		return { type = "for", init = init, cond = cond, step = step, body = body }
	end
	if match("{") then
		local stmts = parse_stmt_list(locals)
		match("}")
		return { type = "block", stmts = stmts }
	end
	return { type = "expr", expr = parse_expr(locals) }
end

function parse_stmt_list(locals)
	local stmts = {}
	while not at("}") and not at("EOF") do
		skip_nl()
		if at("}") or at("EOF") then break end
		local s = parse_stmt(locals)
		if s then stmts[#stmts + 1] = s end
		while match(";") or match("NEWLINE") do end
	end
	return stmts
end

-- Parse function definition
local function parse_function()
	advance() -- Define
	local name = advance().val; match("(")
	local params = {}
	if at("LETTER") then
		params[1] = advance().val
		while match(",") do params[#params + 1] = advance().val end
	end
	match(")"); match("{"); skip_nl()
	-- auto list
	local autos = {}
	if at("Auto") then
		advance()
		while at("LETTER") do
			autos[#autos + 1] = advance().val
			if match("[") then match("]") end
			match(",")
		end
		skip_nl()
	end
	local body = parse_stmt_list()
	match("}")
	functions[name] = { params = params, autos = autos, body = body }
end

-- Evaluate expression AST
local function eval_expr(node, locals)
	if not node then return bignum.new(0) end
	local t = node.type
	if t == "num" then return bignum.new(node.val)
	elseif t == "named" or t == "named_ref" then
		local n = node.named or node
		local idx = n.idx and eval_expr(n.idx, locals) or nil
		return get_named(n.name, idx, locals)
	elseif t == "neg" then
		local v = bignum.copy(eval_expr(node.expr, locals))
		v.neg = not v.neg; v:trim(); return v
	elseif t == "binop" then
		local l = eval_expr(node.left, locals)
		local r = eval_expr(node.right, locals)
		if node.op == "+" then return bignum.add(l, r)
		elseif node.op == "-" then return bignum.sub(l, r)
		elseif node.op == "*" then return bignum.mul(l, r)
		elseif node.op == "/" then return bignum.div(l, r, scale)
		elseif node.op == "%" then return bignum.mod(l, r, scale)
		elseif node.op == "^" then return bignum.pow(l, r)
		end
	elseif t == "rel" then
		local cmp = bignum.compare(eval_expr(node.left, locals), eval_expr(node.right, locals))
		local r = false
		if node.op == "==" then r = cmp == 0
		elseif node.op == "!=" then r = cmp ~= 0
		elseif node.op == "<" then r = cmp < 0
		elseif node.op == ">" then r = cmp > 0
		elseif node.op == "<=" then r = cmp <= 0
		elseif node.op == ">=" then r = cmp >= 0 end
		return bignum.new(r and 1 or 0)
	elseif t == "assign" then
		local val = eval_expr(node.rhs, locals)
		local n = node.named
		if node.op ~= "=" then
			local cur = get_named(n.name, n.idx and eval_expr(n.idx, locals), locals)
			if node.op == "+=" then val = bignum.add(cur, val)
			elseif node.op == "-=" then val = bignum.sub(cur, val)
			elseif node.op == "*=" then val = bignum.mul(cur, val)
			elseif node.op == "/=" then val = bignum.div(cur, val, scale)
			elseif node.op == "%=" then val = bignum.mod(cur, val, scale)
			elseif node.op == "^=" then val = bignum.pow(cur, val) end
		end
		set_named(n.name, val, n.idx and eval_expr(n.idx, locals), locals)
		return val
	elseif t == "prefix" then
		local n = node.named
		local idx = n.idx and eval_expr(n.idx, locals)
		local v = get_named(n.name, idx, locals)
		v = node.op == "++" and bignum.add(v, bignum.new(1)) or bignum.sub(v, bignum.new(1))
		set_named(n.name, v, idx, locals)
		return v
	elseif t == "postfix" then
		local n = node.named
		local idx = n.idx and eval_expr(n.idx, locals)
		local v = get_named(n.name, idx, locals)
		local nv = node.op == "++" and bignum.add(v, bignum.new(1)) or bignum.sub(v, bignum.new(1))
		set_named(n.name, nv, idx, locals)
		return v
	elseif t == "builtin" then
		local v = eval_expr(node.arg, locals)
		if node.fn == "sqrt" then return bignum.sqrt(v, math.max(scale, v.scale))
		elseif node.fn == "length" then
			local s = bignum.to_string(v):gsub("^-", ""):gsub("%.", "")
			return bignum.new(#s)
		elseif node.fn == "scale" then return bignum.new(v.scale) end
	elseif t == "call" then
		local fn = functions[node.name]
		if not fn then
			io.stderr:write("bc: undefined function " .. node.name .. "\n")
			return bignum.new(0)
		end
		local loc = {}
		for i, p in ipairs(fn.params) do loc[p] = eval_expr(node.args[i], locals) or bignum.new(0) end
		for _, a in ipairs(fn.autos) do loc[a] = bignum.new(0) end
		local sig = exec_stmt({ type = "block", stmts = fn.body }, loc)
		if sig and sig[1] == RETURN then return sig[2] or bignum.new(0) end
		return bignum.new(0)
	end
	return bignum.new(0)
end

-- Format output value
local function format_val(v)
	local s = bignum.to_string(v)
	-- Truncate to scale if needed
	if s:find("%.") then
		local int, frac = s:match("^(.-)%.(.*)$")
		local ds = math.max(v.scale, scale)
		if ds == 0 then s = int
		elseif #frac > ds then s = int .. "." .. frac:sub(1, ds)
		elseif #frac < ds then s = int .. "." .. frac .. string.rep("0", ds - #frac) end
	elseif scale > 0 and v.scale == 0 then
		-- don't add decimals to integers unless scale forces it via division
	end
	return s
end

-- Execute statement, returns signal or nil
function exec_stmt(node, locals)
	if not node then return nil end
	local t = node.type
	if t == "expr" then
		local val = eval_expr(node.expr, locals)
		-- Print if not assignment
		if node.expr.type ~= "assign" then
			unistd.write(1, format_val(val) .. "\n")
			last_val = val
		end
	elseif t == "string" then
		unistd.write(1, node.val)
	elseif t == "block" then
		for _, s in ipairs(node.stmts) do
			local sig = exec_stmt(s, locals)
			if sig then return sig end
		end
	elseif t == "if" then
		local cond = eval_expr(node.cond, locals)
		if not cond:is_zero() then return exec_stmt(node.body, locals) end
	elseif t == "while" then
		while true do
			local cond = eval_expr(node.cond, locals)
			if cond:is_zero() then break end
			local sig = exec_stmt(node.body, locals)
			if sig == BREAK then break end
			if sig and sig[1] == RETURN then return sig end
		end
	elseif t == "for" then
		eval_expr(node.init, locals)
		while true do
			local cond = eval_expr(node.cond, locals)
			if cond:is_zero() then break end
			local sig = exec_stmt(node.body, locals)
			if sig == BREAK then break end
			if sig and sig[1] == RETURN then return sig end
			eval_expr(node.step, locals)
		end
	elseif t == "break" then return BREAK
	elseif t == "quit" then os.exit(0)
	elseif t == "return" then
		return { RETURN, node.expr and eval_expr(node.expr, locals) or bignum.new(0) }
	end
	return nil
end

-- Run a source string
local function run(src)
	tokens = tokenize(src)
	tpos = 1
	while not at("EOF") do
		skip_nl()
		if at("EOF") then break end
		if at("Define") then
			parse_function()
		else
			local s = parse_stmt()
			if s then exec_stmt(s) end
		end
		while match(";") or match("NEWLINE") do end
	end
end

-- Math library (-l)
if math_lib then
	run([[
define s(x) {
	auto a, b, c, i, s, n, t
	s = 1
	n = x
	a = x
	for (i = 2; 1; i += 2) {
		a = a * x * x * -1
		b = a / i / (i + 1)
		n = n + b
		if (b == 0) return(n)
	}
	return(n)
}
define c(x) {
	auto i, a, b, n
	n = 1
	a = 1
	for (i = 1; 1; i += 2) {
		a = a * x * x * -1
		b = a / i / (i + 1)
		n = n + b
		if (b == 0) return(n)
	}
	return(n)
}
define a(x) {
	auto i, n, a, s
	s = x
	n = x
	for (i = 1; 1; i += 1) {
		a = x ^ (2 * i + 1) * (0 - 1) ^ i / (2 * i + 1)
		n = n + a
		if (a == 0) return(n)
		if (a == s) return(n)
		s = a
	}
	return(n)
}
define l(x) {
	auto i, n, a, t, s
	t = (x - 1) / (x + 1)
	n = t
	s = t
	for (i = 1; 1; i += 1) {
		t = t * (x - 1) * (x - 1) / (x + 1) / (x + 1)
		a = t / (2 * i + 1)
		n = n + a
		if (a == 0) return(2 * n)
		if (a == s) return(2 * n)
		s = a
	}
	return(2 * n)
}
define e(x) {
	auto a, b, c, i, s
	a = 1
	b = 1
	s = 1
	for (i = 1; 1; i += 1) {
		a = a * x
		b = b * i
		c = a / b
		if (c == 0) return(s)
		s = s + c
	}
	return(s)
}
]])
end

-- Process files then stdin
for _, f in ipairs(files) do
	local fh = io.open(f, "r")
	if not fh then io.stderr:write("bc: cannot open " .. f .. "\n"); os.exit(1) end
	run(fh:read("a")); fh:close()
end
-- Read stdin
local input = io.read("a")
if input and #input > 0 then run(input) end
