-- SPDX-License-Identifier: ISC
-- make/eval_test.lua - busted tests for the variable expansion engine
local eval = require("make.eval")

describe("eval variable expansion", function()
	local env

	before_each(function()
		env = eval.new()
	end)

	it("expands simple variable", function()
		env:set("CC", "gcc")
		assert.equals("gcc", env:expand("$(CC)"))
	end)

	it("expands ${} syntax", function()
		env:set("CC", "gcc")
		assert.equals("gcc", env:expand("${CC}"))
	end)

	it("expands single-char variable", function()
		env:set("X", "hello")
		assert.equals("hello", env:expand("$X"))
	end)

	it("expands $$ to literal $", function()
		assert.equals("$HOME", env:expand("$$HOME"))
	end)

	it("expands nested variables", function()
		env:set("CC", "gcc")
		env:set("FLAGS", "-O2")
		assert.equals("gcc -O2", env:expand("$(CC) $(FLAGS)"))
	end)

	it("recursive variable expands on use", function()
		env:set("A", "hello", "recursive")
		env:set("B", "$(A)", "recursive")
		assert.equals("hello", env:get("B"))
		env:set("A", "world", "recursive")
		assert.equals("world", env:get("B"))
	end)

	it("simple variable expands on assignment", function()
		env:set("A", "hello", "recursive")
		env:set("B", env:expand("$(A)"), "simple")
		env:set("A", "world", "recursive")
		assert.equals("hello", env:get("B"))
	end)

	it("appends with +=", function()
		env:set("FLAGS", "-O2")
		env:append("FLAGS", "-Wall")
		assert.equals("-O2 -Wall", env:get("FLAGS"))
	end)

	it("?= does not override existing", function()
		env:set("CC", "gcc")
		env:set_if_absent("CC", "clang")
		assert.equals("gcc", env:get("CC"))
	end)

	it("?= sets when absent", function()
		env:set_if_absent("CC", "clang")
		assert.equals("clang", env:get("CC"))
	end)

	it("expands suffix substitution $(VAR:.c=.o)", function()
		env:set("SRCS", "foo.c bar.c")
		assert.equals("foo.o bar.o", env:expand("$(SRCS:.c=.o)"))
	end)

	it("expands pattern substitution $(VAR:%.c=%.o)", function()
		env:set("SRCS", "foo.c bar.c")
		assert.equals("foo.o bar.o", env:expand("$(SRCS:%.c=%.o)"))
	end)

	it("expands $(@D) and $(@F)", function()
		env:set("@", "src/foo.o", "simple")
		assert.equals("src/", env:expand("$(@D)"))
		assert.equals("foo.o", env:expand("$(@F)"))
	end)

	it("$(@D) returns . for no directory", function()
		env:set("@", "foo.o", "simple")
		assert.equals(".", env:expand("$(@D)"))
	end)

	it("expands $(subst from,to,text)", function()
		assert.equals("hxllo", env:expand("$(subst e,x,hello)"))
	end)

	it("expands $(patsubst %.c,%.o,foo.c bar.c)", function()
		assert.equals("foo.o bar.o", env:expand("$(patsubst %.c,%.o,foo.c bar.c)"))
	end)

	it("expands $(strip  text )", function()
		assert.equals("a b c", env:expand("$(strip   a  b  c  )"))
	end)

	it("expands $(notdir src/foo.c)", function()
		assert.equals("foo.c", env:expand("$(notdir src/foo.c)"))
	end)

	it("expands $(dir src/foo.c)", function()
		assert.equals("src/", env:expand("$(dir src/foo.c)"))
	end)

	it("expands $(basename src/foo.c)", function()
		assert.equals("src/foo", env:expand("$(basename src/foo.c)"))
	end)

	it("expands $(suffix foo.c bar.h)", function()
		assert.equals(".c .h", env:expand("$(suffix foo.c bar.h)"))
	end)

	it("expands $(addprefix src/,foo.c bar.c)", function()
		assert.equals("src/foo.c src/bar.c", env:expand("$(addprefix src/,foo.c bar.c)"))
	end)

	it("expands $(addsuffix .o,foo bar)", function()
		assert.equals("foo.o bar.o", env:expand("$(addsuffix .o,foo bar)"))
	end)

	it("expands $(filter %.c,foo.c bar.h baz.c)", function()
		assert.equals("foo.c baz.c", env:expand("$(filter %.c,foo.c bar.h baz.c)"))
	end)

	it("expands $(filter-out %.h,foo.c bar.h)", function()
		assert.equals("foo.c", env:expand("$(filter-out %.h,foo.c bar.h)"))
	end)

	it("expands $(sort c a b a)", function()
		assert.equals("a b c", env:expand("$(sort c a b a)"))
	end)

	it("expands $(word 2,a b c)", function()
		assert.equals("b", env:expand("$(word 2,a b c)"))
	end)

	it("expands $(words a b c)", function()
		assert.equals("3", env:expand("$(words a b c)"))
	end)

	it("expands $(firstword a b c)", function()
		assert.equals("a", env:expand("$(firstword a b c)"))
	end)

	it("expands $(lastword a b c)", function()
		assert.equals("c", env:expand("$(lastword a b c)"))
	end)
end)

describe("eval conditionals", function()
	local env

	before_each(function()
		env = eval.new()
	end)

	it("ifdef true branch", function()
		local parser = require("make.parser")
		local nodes = parser.parse("FOO = bar\nifdef FOO\nRESULT = yes\nelse\nRESULT = no\nendif\n")
		env:load(nodes)
		assert.equals("yes", env:get("RESULT"))
	end)

	it("ifdef false branch", function()
		local parser = require("make.parser")
		local nodes = parser.parse("ifdef FOO\nRESULT = yes\nelse\nRESULT = no\nendif\n")
		env:load(nodes)
		assert.equals("no", env:get("RESULT"))
	end)

	it("ifndef true branch", function()
		local parser = require("make.parser")
		local nodes = parser.parse("ifndef FOO\nRESULT = yes\nendif\n")
		env:load(nodes)
		assert.equals("yes", env:get("RESULT"))
	end)
end)

describe("eval pattern matching", function()
	it("matches simple pattern", function()
		assert.equals("foo", eval.pattern_stem("%.o", "foo.o"))
	end)

	it("matches pattern with prefix", function()
		assert.equals("bar", eval.pattern_stem("lib%.a", "libbar.a"))
	end)

	it("returns nil on no match", function()
		assert.is_nil(eval.pattern_stem("%.o", "foo.c"))
	end)

	it("patsubst_word replaces stem", function()
		assert.equals("foo.o", eval.patsubst_word("%.c", "%.o", "foo.c"))
	end)

	it("patsubst_word no match returns original", function()
		assert.equals("foo.h", eval.patsubst_word("%.c", "%.o", "foo.h"))
	end)
end)
