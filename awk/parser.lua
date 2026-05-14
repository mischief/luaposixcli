-- SPDX-License-Identifier: ISC
-- awk/parser.lua - POSIX awk parser producing AST
local lexer = require("awk.lexer")

local M = {}

-- Parser state
local tokens, pos, in_print_ctx

-- Return current token without skipping newlines (newlines are statement terminators)
local function peek()
	return tokens[pos]
end

-- Return current token, skipping over any newlines first
local function peek_skip()
	while pos <= #tokens and tokens[pos].type == "NEWLINE" do pos = pos + 1 end
	return tokens[pos]
end

local function at(typ)
	local t = peek()
	return t and t.type == typ
end

local function at_skip(typ)
	local t = peek_skip()
	return t and t.type == typ
end

local function at_raw(typ) return pos <= #tokens and tokens[pos].type == typ end

-- Consume a token of the expected type (skipping newlines), or error
local function consume(typ)
	local t = peek_skip()
	if not t then error("unexpected end of input, expected " .. typ) end
	if t.type ~= typ then error("expected " .. typ .. " got " .. t.type .. " (" .. tostring(t.value) .. ")") end
	pos = pos + 1
	return t
end

local function match(typ)
	if at(typ) then pos = pos + 1; return tokens[pos - 1] end
	return nil
end

local function match_skip(typ)
	if at_skip(typ) then pos = pos + 1; return tokens[pos - 1] end
	return nil
end

local function skip_newlines()
	while pos <= #tokens and tokens[pos].type == "NEWLINE" do pos = pos + 1 end
end

-- Skip statement terminators (newlines and semicolons). Returns true if any were found.
local function skip_terminators()
	local found = false
	while pos <= #tokens and (tokens[pos].type == "NEWLINE" or tokens[pos].type == ";") do
		pos = pos + 1; found = true
	end
	return found
end

-- Forward declarations
local parse_expr, parse_print_expr, parse_action, parse_statement, parse_simple_stmt

-- Precedence levels for Pratt parsing
local PREC = {
	ASSIGN = 1, TERNARY = 2, OR = 3, AND = 4, IN = 5,
	MATCH = 6, CMP = 7, CONCAT = 8, ADD = 9, MUL = 10,
	UNARY = 11, POWER = 12, PREFIX = 13, FIELD = 14, POSTFIX = 15,
}

local binary_prec = {
	["OR"] = PREC.OR, ["AND"] = PREC.AND,
	["In"] = PREC.IN,
	["~"] = PREC.MATCH, ["NO_MATCH"] = PREC.MATCH,
	["<"] = PREC.CMP, ["LE"] = PREC.CMP, ["NE"] = PREC.CMP,
	["EQ"] = PREC.CMP, [">"] = PREC.CMP, ["GE"] = PREC.CMP,
	["+"] = PREC.ADD, ["-"] = PREC.ADD,
	["*"] = PREC.MUL, ["/"] = PREC.MUL, ["%"] = PREC.MUL,
	["^"] = PREC.POWER,
}

local right_assoc = { ["^"] = true, ["?"] = true }

local assign_ops = {
	["="] = "=", ADD_ASSIGN = "+=", SUB_ASSIGN = "-=",
	MUL_ASSIGN = "*=", DIV_ASSIGN = "/=", MOD_ASSIGN = "%=", POW_ASSIGN = "^=",
}

-- Check if an AST node is a valid assignment target (variable, field, or array element)
local function is_lvalue(node)
	return node.type == "name" or node.type == "field" or node.type == "index"
end

-- Parse a getline expression. left is the pipe source (expr | getline) or nil.
-- Handles: getline, getline var, getline < file, getline var < file, expr | getline [var]
local function parse_getline(left)
	-- getline [var] [< expr] or expr | getline [var]
	consume("Getline")
	local var, source
	-- optional lvalue
	local t = peek()
	if t and (t.type == "NAME" or t.type == "$") then
		local saved = pos
		local expr = parse_expr(PREC.POSTFIX)
		if is_lvalue(expr) then
			var = expr
		else
			pos = saved
		end
	end
	-- optional < file
	if at("<") then
		pos = pos + 1
		source = { type = "redir_in", expr = parse_expr(PREC.CONCAT) }
	end
	local node = { type = "getline", var = var, source = source }
	if left then node.pipe_from = left end
	return node
end

-- Parse a function call argument list. Opening ( has not been consumed yet.
local function parse_call(name, is_builtin)
	consume("(")
	local args = {}
	if not at(")") then
		args[1] = parse_expr(0)
		while match(",") do
			skip_newlines()
			args[#args + 1] = parse_expr(0)
		end
	end
	consume(")")
	return { type = "call", func = name, builtin = is_builtin, args = args }
end

-- Null denotation: parse a prefix expression or atom (Pratt parser).
-- Handles literals, unary operators, prefix ++/--, parenthesized exprs,
-- field references ($), function calls, and getline.
local function nud()
	local t = peek_skip()
	if not t then error("unexpected end of input in expression") end

	if t.type == "NUMBER" then
		pos = pos + 1
		return { type = "number", value = tonumber(t.value) }
	elseif t.type == "STRING" then
		pos = pos + 1
		return { type = "string", value = t.value }
	elseif t.type == "ERE" then
		pos = pos + 1
		return { type = "ere", value = t.value }
	elseif t.type == "$" then
		pos = pos + 1
		local expr = parse_expr(PREC.FIELD)
		return { type = "field", expr = expr }
	elseif t.type == "!" then
		pos = pos + 1
		return { type = "unary", op = "!", expr = parse_expr(PREC.UNARY) }
	elseif t.type == "+" then
		pos = pos + 1
		return { type = "unary", op = "+", expr = parse_expr(PREC.UNARY) }
	elseif t.type == "-" then
		pos = pos + 1
		return { type = "unary", op = "-", expr = parse_expr(PREC.UNARY) }
	elseif t.type == "INCR" then
		pos = pos + 1
		local expr = parse_expr(PREC.UNARY)
		return { type = "incr", expr = expr, pre = true }
	elseif t.type == "DECR" then
		pos = pos + 1
		local expr = parse_expr(PREC.UNARY)
		return { type = "decr", expr = expr, pre = true }
	elseif t.type == "(" then
		pos = pos + 1
		skip_newlines()
		local expr = parse_expr(0)
		-- check for (expr_list) in NAME
		if at(",") then
			local list = { expr }
			while match(",") do
				skip_newlines()
				list[#list + 1] = parse_expr(0)
			end
			consume(")")
			if at("In") then
				pos = pos + 1
				local arr = consume("NAME")
				return { type = "in", index = list, array = arr.value }
			end
			-- otherwise it's just a parenthesized multiple_expr_list (e.g. in print)
			return { type = "group", exprs = list }
		end
		consume(")")
		return expr
	elseif t.type == "NAME" then
		pos = pos + 1
		-- check for array subscript
		if at("[") then
			pos = pos + 1
			local indices = { parse_expr(0) }
			while match(",") do
				skip_newlines()
				indices[#indices + 1] = parse_expr(0)
			end
			consume("]")
			return { type = "index", array = t.value, indices = indices }
		end
		return { type = "name", name = t.value }
	elseif t.type == "FUNC_NAME" then
		pos = pos + 1
		return parse_call(t.value, false)
	elseif t.type == "BUILTIN_FUNC_NAME" then
		pos = pos + 1
		if at("(") then
			return parse_call(t.value, true)
		end
		-- length without parens = length($0)
		return { type = "call", func = t.value, builtin = true, args = {} }
	elseif t.type == "Getline" then
		return parse_getline(nil)
	else
		error("unexpected token in expression: " .. t.type .. " (" .. tostring(t.value) .. ")")
	end
end

-- Can this token start an expression (for concat detection)?
local function can_start_expr(t)
	if not t then return false end
	local typ = t.type
	return typ == "NUMBER" or typ == "STRING" or typ == "NAME" or typ == "FUNC_NAME"
		or typ == "BUILTIN_FUNC_NAME" or typ == "ERE" or typ == "$"
		or typ == "(" or typ == "!" or typ == "INCR" or typ == "DECR"
		or typ == "Getline"
end

-- Left denotation: parse infix/postfix operators (Pratt parser).
-- Handles binary ops, assignments, postfix ++/--, ternary, string concat,
-- pipe-to-getline, and the "in" operator.
local function led(left, min_prec)
	local t = peek()
	if not t or t.type == "NEWLINE" then return nil end

	-- Assignment operators
	if assign_ops[t.type] and is_lvalue(left) then
		if PREC.ASSIGN >= min_prec then
			pos = pos + 1
			return { type = "assign", op = assign_ops[t.type], target = left, value = parse_expr(PREC.ASSIGN - 1) }
		end
	end

	-- Postfix ++ --
	if t.type == "INCR" and is_lvalue(left) then
		if PREC.POSTFIX >= min_prec then
			pos = pos + 1
			return { type = "incr", expr = left, pre = false }
		end
	end
	if t.type == "DECR" and is_lvalue(left) then
		if PREC.POSTFIX >= min_prec then
			pos = pos + 1
			return { type = "decr", expr = left, pre = false }
		end
	end

	-- Ternary
	if t.type == "?" and PREC.TERNARY >= min_prec then
		pos = pos + 1
		local then_ = parse_expr(0)
		consume(":")
		local else_ = parse_expr(PREC.TERNARY - 1)
		return { type = "ternary", cond = left, then_ = then_, else_ = else_ }
	end

	-- Binary operators
	local prec = binary_prec[t.type]
	if prec and prec >= min_prec then
		-- In print context, > >> | are output redirection, not operators
		if in_print_ctx and (t.type == ">" or t.type == "|" or t.type == "APPEND") then return nil end
		pos = pos + 1
		if t.type == "In" then
			local arr = consume("NAME")
			return { type = "in", index = { left }, array = arr.value }
		end
		skip_newlines() -- newlines allowed after && || ,
		local rprec = right_assoc[t.type] and prec - 1 or prec
		local right = parse_expr(rprec)
		local op = t.value
		if t.type == "OR" then op = "||"
		elseif t.type == "AND" then op = "&&"
		elseif t.type == "EQ" then op = "=="
		elseif t.type == "NE" then op = "!="
		elseif t.type == "LE" then op = "<="
		elseif t.type == "GE" then op = ">="
		elseif t.type == "NO_MATCH" then op = "!~"
		end
		return { type = "binary", op = op, left = left, right = right }
	end

	-- Pipe to getline
	if t.type == "|" and PREC.ADD >= min_prec then
		-- check if getline follows
		local saved = pos
		pos = pos + 1
		skip_newlines()
		if at("Getline") then
			return parse_getline(left)
		end
		pos = saved
	end

	-- String concatenation (implicit - no operator token)
	if PREC.CONCAT >= min_prec then
		local nt = peek()
		if can_start_expr(nt) and not binary_prec[nt.type] and nt.type ~= "In" then
			local right = parse_expr(PREC.CONCAT)
			return { type = "concat", left = left, right = right }
		end
	end

	-- Array subscript after expression (for $expr[...])
	if t.type == "[" and left.type ~= "index" and PREC.POSTFIX >= min_prec then
		-- Only valid for NAME lvalues, handled in nud
	end

	return nil
end

-- Parse an expression using Pratt precedence climbing.
-- min_prec controls the minimum binding power (0 = parse everything).
function parse_expr(min_prec)
	min_prec = min_prec or 0
	local node = nud()
	while true do
		local result = led(node, min_prec)
		if not result then break end
		node = result
	end
	return node
end

-- print_expr: like expr but > and | and >> are output redirection, not operators
function parse_print_expr(min_prec)
	-- For simplicity, parse a full expr but stop at > >> |
	-- We achieve this by parsing with the regular parser but treating > >> | as terminators
	-- Actually, we just parse normally and let the print statement handle redirection
	return parse_expr(min_prec or 0)
end

-- Parse an output redirection (> file, >> file, | cmd) after a print/printf statement
local function parse_output_redir()
	local t = peek()
	if not t then return nil end
	if t.type == ">" then
		pos = pos + 1
		return { redir = ">", expr = parse_expr(0) }
	elseif t.type == "APPEND" then
		pos = pos + 1
		return { redir = ">>", expr = parse_expr(0) }
	elseif t.type == "|" then
		pos = pos + 1
		return { redir = "|", expr = parse_expr(0) }
	end
	return nil
end

-- Parse print/printf argument list and optional output redirection.
-- In print context, > >> | are redirection operators, not comparison/pipe.
local function parse_print_stmt(is_printf)
	local args = {}
	local output

	-- Check for ( expr_list ) form
	if at("(") then
		local saved = pos
		pos = pos + 1
		skip_newlines()
		local first = parse_expr(0)
		if at(",") then
			-- multiple_expr_list in parens
			args = { first }
			while match(",") do
				skip_newlines()
				args[#args + 1] = parse_expr(0)
			end
			consume(")")
			output = parse_output_redir()
			return { type = is_printf and "printf" or "print", args = args, output = output }
		elseif at(")") then
			pos = pos + 1
			-- could be print(expr) > file or just print (expr)
			output = parse_output_redir()
			if output then
				args = { first }
				return { type = is_printf and "printf" or "print", args = args, output = output }
			end
			-- It was print (expr), treat as single arg
			args = { first }
			-- check for more args
			-- Actually after ), check for > >> |
			output = parse_output_redir()
			return { type = is_printf and "printf" or "print", args = args, output = output }
		else
			-- Not a parenthesized list, backtrack
			pos = saved
		end
	end

	-- Parse print_expr_list: expressions separated by commas, stopping at > >> | ; newline
	local t = peek()
	if t and t.type ~= "NEWLINE" and t.type ~= ";" and t.type ~= "}" and t.type ~= ">" and t.type ~= "APPEND" and t.type ~= "|" then
		in_print_ctx = true
		args[1] = parse_expr(0)
		while true do
			local nt = peek()
			if not nt or nt.type == ">" or nt.type == "APPEND" or nt.type == "|" then break end
			if not match(",") then break end
			skip_newlines()
			args[#args + 1] = parse_expr(0)
		end
		in_print_ctx = false
	end

	output = parse_output_redir()
	return { type = is_printf and "printf" or "print", args = args, output = output }
end

-- Parse a simple statement: delete, print, printf, or an expression statement
function parse_simple_stmt()
	local t = peek()
	if not t then return nil end

	if t.type == "Delete" then
		pos = pos + 1
		local name = consume("NAME")
		if match("[") then
			local indices = { parse_expr(0) }
			while match(",") do indices[#indices + 1] = parse_expr(0) end
			consume("]")
			return { type = "delete", target = { type = "index", array = name.value, indices = indices } }
		end
		return { type = "delete", target = { type = "name", name = name.value } }
	elseif t.type == "Print" then
		pos = pos + 1
		return parse_print_stmt(false)
	elseif t.type == "Printf" then
		pos = pos + 1
		return parse_print_stmt(true)
	else
		return parse_expr(0)
	end
end

-- Parse a statement: compound (block), control flow (if/while/for/do), or simple
function parse_statement()
	local t = peek()
	if not t then return nil end

	if t.type == "{" then
		return parse_action()
	elseif t.type == "If" then
		pos = pos + 1
		consume("(")
		local cond = parse_expr(0)
		consume(")")
		skip_newlines()
		local then_ = parse_statement()
		local else_
		-- peek ahead for else without consuming terminators permanently
		local saved = pos
		skip_terminators()
		if at("Else") then
			pos = pos + 1
			skip_newlines()
			else_ = parse_statement()
		else
			pos = saved -- restore: terminator belongs to enclosing block
		end
		return { type = "if", cond = cond, then_ = then_, else_ = else_ }
	elseif t.type == "While" then
		pos = pos + 1
		consume("(")
		local cond = parse_expr(0)
		consume(")")
		skip_newlines()
		local body = parse_statement()
		return { type = "while", cond = cond, body = body }
	elseif t.type == "Do" then
		pos = pos + 1
		skip_newlines()
		local body = parse_statement()
		skip_terminators()
		consume("While")
		consume("(")
		local cond = parse_expr(0)
		consume(")")
		return { type = "do_while", body = body, cond = cond }
	elseif t.type == "For" then
		pos = pos + 1
		consume("(")
		-- for (var in array) or for (init; cond; step)
		-- Try for-in first
		local saved = pos
		if at("NAME") then
			local name = tokens[pos]
			pos = pos + 1
			if at("In") then
				pos = pos + 1
				local arr = consume("NAME")
				consume(")")
				skip_newlines()
				local body = parse_statement()
				return { type = "for_in", var = name.value, array = arr.value, body = body }
			end
			pos = saved
		end
		-- Regular for
		local init
		if not at(";") then init = parse_simple_stmt() end
		consume(";")
		local cond
		if not at(";") then cond = parse_expr(0) end
		consume(";")
		local step
		if not at(")") then step = parse_simple_stmt() end
		consume(")")
		skip_newlines()
		local body = parse_statement()
		return { type = "for", init = init, cond = cond, step = step, body = body }
	elseif t.type == "Break" then
		pos = pos + 1; return { type = "break" }
	elseif t.type == "Continue" then
		pos = pos + 1; return { type = "continue" }
	elseif t.type == "Next" then
		pos = pos + 1; return { type = "next" }
	elseif t.type == "Exit" then
		pos = pos + 1
		local expr
		local nt = peek()
		if nt and nt.type ~= "NEWLINE" and nt.type ~= ";" and nt.type ~= "}" then
			expr = parse_expr(0)
		end
		return { type = "exit", expr = expr }
	elseif t.type == "Return" then
		pos = pos + 1
		local expr
		local nt = peek()
		if nt and nt.type ~= "NEWLINE" and nt.type ~= ";" and nt.type ~= "}" then
			expr = parse_expr(0)
		end
		return { type = "return", expr = expr }
	else
		return parse_simple_stmt()
	end
end

-- Parse an action block: { statement_list }
function parse_action()
	consume("{")
	skip_newlines()
	local stmts = {}
	while not at("}") do
		local stmt = parse_statement()
		if stmt then stmts[#stmts + 1] = stmt end
		if not skip_terminators() then
			if not at("}") then break end
		end
	end
	consume("}")
	return { type = "block", stmts = stmts }
end

-- Parse a pattern: BEGIN, END, expression, or range (expr, expr)
local function parse_pattern()
	local t = peek()
	if not t or t.type == "{" then return nil end
	if t.type == "Begin" then pos = pos + 1; return { type = "BEGIN" } end
	if t.type == "End" then pos = pos + 1; return { type = "END" } end

	local expr = parse_expr(0)
	-- Range pattern: expr , expr
	if match(",") then
		skip_newlines()
		local to = parse_expr(0)
		return { type = "range", from = expr, to = to }
	end
	return expr
end

-- Parse an awk program source string and return an AST.
-- The AST root is {type="program", rules={...}} where each rule is either
-- a pattern-action pair {type="rule", pattern=..., action=...} or
-- a function definition {type="function", name=..., params={...}, body=...}.
function M.parse(src)
	tokens = lexer.tokenize(src)
	pos = 1
	in_print_ctx = false

	local program = { type = "program", rules = {} }

	while pos <= #tokens do
		skip_terminators()
		if pos > #tokens then break end

		local t = peek()
		if not t then break end

		-- Function definition
		if t.type == "Function" then
			pos = pos + 1
			local name_tok = peek()
			local name_val
			if name_tok.type == "FUNC_NAME" then
				-- FUNC_NAME already consumed the ( check, so ( follows
				name_val = name_tok.value
				pos = pos + 1
				consume("(")
			elseif name_tok.type == "NAME" then
				name_val = name_tok.value
				pos = pos + 1
				consume("(")
			else
				error("expected function name")
			end
			local params = {}
			if not at(")") then
				params[1] = consume("NAME").value
				while match(",") do
					params[#params + 1] = consume("NAME").value
				end
			end
			consume(")")
			skip_newlines()
			local body = parse_action()
			program.rules[#program.rules + 1] = {
				type = "function", name = name_tok.value, params = params, body = body,
			}
		else
			-- pattern-action rule
			local pattern = parse_pattern()
			local action
			skip_newlines()
			if at("{") then
				action = parse_action()
			end
			-- At least one of pattern or action must exist
			if pattern or action then
				program.rules[#program.rules + 1] = { type = "rule", pattern = pattern, action = action }
			end
		end
	end

	return program
end

return M
