-- SPDX-License-Identifier: ISC
local lexer = require("sh.lexer")

-- helper: extract first pipeline from first chain of first list entry
local function first_pipeline(line)
	local list = lexer.tokenize(line)
	return list[1].chain[1].pipeline
end

-- helper: flatten all words from first pipeline
local function tok(line)
	local p = first_pipeline(line)
	local words = {}
	for _, seg in ipairs(p) do
		for _, w in ipairs(seg) do
			words[#words + 1] = w
		end
	end
	return words
end

describe("sh.lexer", function()
	describe("basic words", function()
		it("splits on spaces", function()
			assert.are.same({ "echo", "hello", "world" }, tok("echo hello world"))
		end)
		it("handles leading/trailing blanks", function()
			assert.are.same({ "echo" }, tok("  echo  "))
		end)
		it("empty line", function()
			local p = first_pipeline("")
			assert.are.equal(1, #p)
			assert.are.equal(0, #p[1])
		end)
	end)

	describe("comments", function()
		it("strips # comment", function()
			assert.are.same({ "echo", "hi" }, tok("echo hi # comment"))
		end)
		it("line that is only a comment", function()
			assert.are.same({}, tok("# just a comment"))
		end)
	end)

	describe("single quotes", function()
		it("preserves spaces", function()
			assert.are.same({ "echo", "hello world" }, tok("echo 'hello world'"))
		end)
		it("preserves special chars", function()
			assert.are.same({ "a|b" }, tok("'a|b'"))
		end)
	end)

	describe("double quotes", function()
		it("preserves spaces", function()
			assert.are.same({ "echo", "hello world" }, tok('echo "hello world"'))
		end)
		it("adjacent segments merge", function()
			assert.are.same({ "helloworld" }, tok('"hello"world'))
		end)
	end)

	describe("backslash escape", function()
		it("escapes space", function()
			assert.are.same({ "hello world" }, tok("hello\\ world"))
		end)
		it("escapes pipe", function()
			assert.are.same({ "a|b" }, tok("a\\|b"))
		end)
	end)

	describe("pipes", function()
		it("splits pipeline", function()
			local p = first_pipeline("echo foo | cat")
			assert.are.equal(2, #p)
			assert.are.same({ "echo", "foo" }, p[1])
			assert.are.same({ "cat" }, p[2])
		end)
		it("three-stage", function()
			local p = first_pipeline("a | b | c")
			assert.are.equal(3, #p)
		end)
		it("pipe in quotes not separator", function()
			local p = first_pipeline("echo 'a|b'")
			assert.are.equal(1, #p)
			assert.are.same({ "echo", "a|b" }, p[1])
		end)
	end)

	describe("list operators", function()
		it("; splits into separate list entries", function()
			local list = lexer.tokenize("echo a; echo b")
			assert.are.equal(2, #list)
		end)
		it("&& creates chain", function()
			local list = lexer.tokenize("echo a && echo b")
			assert.are.equal(1, #list)
			assert.are.equal(2, #list[1].chain)
			assert.are.equal("&&", list[1].chain[1].op)
		end)
		it("|| creates chain", function()
			local list = lexer.tokenize("echo a || echo b")
			assert.are.equal(1, #list)
			assert.are.equal(2, #list[1].chain)
			assert.are.equal("||", list[1].chain[1].op)
		end)
		it("& marks async", function()
			local list = lexer.tokenize("sleep 1 &")
			assert.are.equal(2, #list)
			assert.is_true(list[1].async)
		end)
	end)
end)
