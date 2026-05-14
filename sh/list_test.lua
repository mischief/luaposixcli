-- SPDX-License-Identifier: ISC
-- sh/list_test.lua: tests for &&, ||, ; list operators
-- These are integration tests that run the shell

local function sh(input)
	local src = debug.getinfo(1, "S").source:match("^@(.+/)")
	local cmd = string.format("lua5.4 %ssh.lua -c '%s' 2>/dev/null", src, input)
	local f = io.popen(cmd)
	local out = f:read("*a"):gsub("\n$", "")
	f:close()
	return out
end

describe("list operators", function()
	describe(";", function()
		it("runs commands sequentially", function()
			assert.equal("a\nb", sh("echo a; echo b"))
		end)
		it("trailing ; is ok", function()
			assert.equal("a", sh("echo a;"))
		end)
	end)

	describe("&&", function()
		it("runs second if first succeeds", function()
			assert.equal("a\nb", sh("echo a && echo b"))
		end)
		it("skips second if first fails", function()
			assert.equal("", sh("false && echo b"))
		end)
	end)

	describe("||", function()
		it("skips second if first succeeds", function()
			assert.equal("a", sh("echo a || echo b"))
		end)
		it("runs second if first fails", function()
			assert.equal("b", sh("false || echo b"))
		end)
	end)

	describe("mixed", function()
		it("&& has same precedence as || (left assoc)", function()
			-- false && echo foo || echo bar -> bar
			assert.equal("bar", sh("false && echo foo || echo bar"))
		end)
		it("true || echo foo && echo bar -> bar", function()
			assert.equal("bar", sh("true || echo foo && echo bar"))
		end)
		it("; separates independent lists", function()
			assert.equal("b", sh("false && echo a; echo b"))
		end)
	end)
end)
