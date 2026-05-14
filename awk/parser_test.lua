-- SPDX-License-Identifier: ISC
-- awk/parser_test.lua - busted tests for awk parser
local parser = require("awk.parser")

describe("awk parser", function()
	it("parses simple pattern-action", function()
		local ast = parser.parse('/foo/ { print $1 }')
		assert.equals("program", ast.type)
		assert.equals(1, #ast.rules)
		local rule = ast.rules[1]
		assert.equals("rule", rule.type)
		assert.equals("ere", rule.pattern.type)
		assert.equals("foo", rule.pattern.value)
		assert.equals("block", rule.action.type)
		local stmt = rule.action.stmts[1]
		assert.equals("print", stmt.type)
		assert.equals("field", stmt.args[1].type)
	end)

	it("parses BEGIN/END", function()
		local ast = parser.parse('BEGIN { x = 1 } END { print x }')
		assert.equals(2, #ast.rules)
		assert.equals("BEGIN", ast.rules[1].pattern.type)
		assert.equals("END", ast.rules[2].pattern.type)
	end)

	it("parses function definitions", function()
		local ast = parser.parse('function max(a, b) { if (a > b) return a; return b }')
		assert.equals(1, #ast.rules)
		local fn = ast.rules[1]
		assert.equals("function", fn.type)
		assert.equals("max", fn.name)
		assert.same({ "a", "b" }, fn.params)
		assert.equals("block", fn.body.type)
	end)

	it("parses arithmetic with correct precedence", function()
		local ast = parser.parse('{ x = 1 + 2 * 3 }')
		local assign = ast.rules[1].action.stmts[1]
		assert.equals("assign", assign.type)
		local val = assign.value
		assert.equals("binary", val.type)
		assert.equals("+", val.op)
		assert.equals(1, val.left.value)
		assert.equals("binary", val.right.type)
		assert.equals("*", val.right.op)
	end)

	it("parses if/else", function()
		local ast = parser.parse('{ if (x > 0) print "pos"; else print "neg" }')
		local stmt = ast.rules[1].action.stmts[1]
		assert.equals("if", stmt.type)
		assert.equals("binary", stmt.cond.type)
		assert.equals(">", stmt.cond.op)
		assert.truthy(stmt.then_)
		assert.truthy(stmt.else_)
	end)

	it("parses while loop", function()
		local ast = parser.parse('{ while (i < 10) i++ }')
		local stmt = ast.rules[1].action.stmts[1]
		assert.equals("while", stmt.type)
		assert.equals("binary", stmt.cond.type)
		assert.equals("incr", stmt.body.type)
	end)

	it("parses for loop", function()
		local ast = parser.parse('{ for (i = 0; i < 10; i++) print i }')
		local stmt = ast.rules[1].action.stmts[1]
		assert.equals("for", stmt.type)
		assert.equals("assign", stmt.init.type)
		assert.equals("binary", stmt.cond.type)
		assert.equals("incr", stmt.step.type)
	end)

	it("parses for-in loop", function()
		local ast = parser.parse('{ for (k in arr) print k }')
		local stmt = ast.rules[1].action.stmts[1]
		assert.equals("for_in", stmt.type)
		assert.equals("k", stmt.var)
		assert.equals("arr", stmt.array)
	end)

	it("parses field references", function()
		local ast = parser.parse('{ print $1, $(NF-1) }')
		local stmt = ast.rules[1].action.stmts[1]
		assert.equals("field", stmt.args[1].type)
		assert.equals("number", stmt.args[1].expr.type)
		assert.equals(1, stmt.args[1].expr.value)
		assert.equals("field", stmt.args[2].type)
		assert.equals("binary", stmt.args[2].expr.type)
	end)

	it("parses array indexing", function()
		local ast = parser.parse('{ a[1] = "x"; print a[1] }')
		local assign = ast.rules[1].action.stmts[1]
		assert.equals("assign", assign.type)
		assert.equals("index", assign.target.type)
		assert.equals("a", assign.target.array)
	end)

	it("parses compound assignments", function()
		local ast = parser.parse('{ x += 5; y *= 2 }')
		local s1 = ast.rules[1].action.stmts[1]
		local s2 = ast.rules[1].action.stmts[2]
		assert.equals("assign", s1.type)
		assert.equals("+=", s1.op)
		assert.equals("assign", s2.type)
		assert.equals("*=", s2.op)
	end)

	it("parses string concatenation", function()
		local ast = parser.parse('{ x = "a" "b" "c" }')
		local val = ast.rules[1].action.stmts[1].value
		assert.equals("concat", val.type)
	end)

	it("parses print with output redirection", function()
		local ast = parser.parse('{ print "hello" > "/tmp/out" }')
		local stmt = ast.rules[1].action.stmts[1]
		assert.equals("print", stmt.type)
		assert.truthy(stmt.output)
		assert.equals(">", stmt.output.redir)
	end)

	it("parses printf", function()
		local ast = parser.parse('{ printf "%d\\n", x }')
		local stmt = ast.rules[1].action.stmts[1]
		assert.equals("printf", stmt.type)
		assert.equals(2, #stmt.args)
	end)

	it("parses getline", function()
		local ast = parser.parse('{ getline line < "/etc/passwd" }')
		local stmt = ast.rules[1].action.stmts[1]
		assert.equals("getline", stmt.type)
		assert.truthy(stmt.var)
		assert.truthy(stmt.source)
	end)

	it("parses pattern range", function()
		local ast = parser.parse('/start/, /stop/ { print }')
		local rule = ast.rules[1]
		assert.equals("range", rule.pattern.type)
		assert.equals("ere", rule.pattern.from.type)
		assert.equals("start", rule.pattern.from.value)
	end)

	it("parses do-while", function()
		local ast = parser.parse('{ do { x++ } while (x < 10) }')
		local stmt = ast.rules[1].action.stmts[1]
		assert.equals("do_while", stmt.type)
		assert.truthy(stmt.body)
		assert.truthy(stmt.cond)
	end)

	it("parses ternary", function()
		local ast = parser.parse('{ x = a > b ? a : b }')
		local val = ast.rules[1].action.stmts[1].value
		assert.equals("ternary", val.type)
	end)

	it("parses regex match operators", function()
		local ast = parser.parse('$2 ~ /xyz/ && $4 !~ /xyz/')
		local rule = ast.rules[1]
		assert.equals("binary", rule.pattern.type)
		assert.equals("&&", rule.pattern.op)
	end)

	it("parses builtin function calls", function()
		local ast = parser.parse('{ n = split($0, a, ":") }')
		local assign = ast.rules[1].action.stmts[1]
		assert.equals("call", assign.value.type)
		assert.equals("split", assign.value.func)
		assert.equals(3, #assign.value.args)
	end)

	it("parses expression as pattern (no action)", function()
		local ast = parser.parse('$3 > 5')
		assert.equals(1, #ast.rules)
		local rule = ast.rules[1]
		assert.equals("rule", rule.type)
		assert.equals("binary", rule.pattern.type)
		assert.is_nil(rule.action)
	end)

	it("parses action without pattern", function()
		local ast = parser.parse('{ print NR ":" NF }')
		local rule = ast.rules[1]
		assert.is_nil(rule.pattern)
		assert.truthy(rule.action)
	end)

	it("parses delete statement", function()
		local ast = parser.parse('{ delete arr[i] }')
		local stmt = ast.rules[1].action.stmts[1]
		assert.equals("delete", stmt.type)
		assert.equals("index", stmt.target.type)
	end)
end)
