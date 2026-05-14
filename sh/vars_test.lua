-- SPDX-License-Identifier: ISC
-- sh/vars_test.lua
local env = require("sh.env")
local expand = require("sh.expand")

describe("sh.env", function()
	before_each(function()
		env.reset()
	end)

	describe("variable assignment", function()
		it("sets and gets a variable", function()
			env.set("FOO", "bar")
			assert.equal("bar", env.get("FOO"))
		end)

		it("unset removes a variable", function()
			env.set("FOO", "bar")
			env.unset("FOO")
			assert.is_nil(env.get("FOO"))
		end)

		it("export marks variable for export", function()
			env.set("FOO", "bar")
			env.export("FOO")
			assert.is_true(env.is_exported("FOO"))
		end)

		it("unexported variable is not exported", function()
			env.set("FOO", "bar")
			assert.is_false(env.is_exported("FOO"))
		end)

		it("unset also clears export flag", function()
			env.set("FOO", "bar")
			env.export("FOO")
			env.unset("FOO")
			assert.is_false(env.is_exported("FOO"))
		end)

		it("inherits from process environment", function()
			-- HOME should be set from the real environment
			assert.is_string(env.get("HOME"))
		end)
	end)

	describe("special parameters", function()
		it("$? reflects last exit status", function()
			env.set_status(42)
			assert.equal("42", env.get("?"))
		end)

		it("$$ is the shell PID", function()
			local pid = env.get("$")
			assert.is_string(pid)
			assert.is_true(tonumber(pid) > 0)
		end)

		it("$0 is the shell name", function()
			env.set_argv({ "sh", "a", "b", "c" })
			assert.equal("sh", env.get("0"))
		end)

		it("$# is the count of positional parameters", function()
			env.set_argv({ "sh", "a", "b", "c" })
			assert.equal("3", env.get("#"))
		end)

		it("$@ expands to all positional parameters space-joined", function()
			env.set_argv({ "sh", "a", "b", "c" })
			assert.equal("a b c", env.get("@"))
		end)

		it("$* expands to all positional parameters space-joined", function()
			env.set_argv({ "sh", "a", "b", "c" })
			assert.equal("a b c", env.get("*"))
		end)

		it("$! is empty when no background job run", function()
			assert.equal("", env.get("!"))
		end)

		it("$- is empty (no option flags implemented)", function()
			assert.equal("", env.get("-"))
		end)
	end)
end)

describe("sh.expand", function()
	before_each(function()
		env.reset()
	end)

	it("expands $VAR", function()
		env.set("FOO", "hello")
		assert.equal("hello", expand.word("$FOO"))
	end)

	it("expands ${VAR}", function()
		env.set("FOO", "world")
		assert.equal("world", expand.word("${FOO}"))
	end)

	it("unset variable expands to empty string", function()
		assert.equal("", expand.word("$UNSET_XYZ"))
	end)

	it("expands $? to last status", function()
		env.set_status(1)
		assert.equal("1", expand.word("$?"))
	end)

	it("expands $$ to shell PID", function()
		local pid = expand.word("$$")
		assert.is_true(tonumber(pid) > 0)
	end)

	it("expands mixed text and variable", function()
		env.set("NAME", "world")
		assert.equal("hello world", expand.word("hello $NAME"))
	end)

	it("does not expand inside single quotes", function()
		env.set("FOO", "bar")
		assert.equal("$FOO", expand.word("'$FOO'"))
	end)

	it("expands inside double quotes", function()
		env.set("FOO", "bar")
		assert.equal("bar", expand.word('"$FOO"'))
	end)

	it("is_assignment detects NAME=value", function()
		assert.is_truthy(expand.is_assignment("FOO=bar"))
		assert.is_falsy(expand.is_assignment("echo"))
		assert.is_falsy(expand.is_assignment("=bar"))
	end)

	it("parse_assignment splits NAME=value", function()
		local name, val = expand.parse_assignment("FOO=hello world")
		assert.equal("FOO", name)
		assert.equal("hello world", val)
	end)
end)
