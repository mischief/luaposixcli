-- SPDX-License-Identifier: ISC
-- sh/cmdsub_test.lua: tests for $(...) command substitution

local function sh(input)
	local src = debug.getinfo(1, "S").source:match("^@(.+/)")
	local cmd = string.format("lua5.4 %ssh.lua -c '%s' 2>/dev/null", src, input)
	local f = io.popen(cmd)
	local out = f:read("*a"):gsub("\n$", "")
	f:close()
	return out
end

describe("command substitution", function()
	it("basic $(echo hello)", function()
		assert.equal("hello", sh("echo $(echo hello)"))
	end)

	it("captures multi-word output", function()
		assert.equal("hello world", sh("echo $(echo hello world)"))
	end)

	it("strips trailing newlines", function()
		assert.equal("foo", sh("echo $(printf foo)"))
	end)

	it("embedded in string", function()
		assert.equal("hi there", sh("echo hi $(echo there)"))
	end)

	it("inside double quotes", function()
		assert.equal("hello world", sh('echo "$(echo hello world)"'))
	end)

	it("nested substitution", function()
		assert.equal("inner", sh("echo $(echo $(echo inner))"))
	end)

	it("assigns to variable", function()
		assert.equal("bar", sh("X=$(echo bar); echo $X"))
	end)

	it("in test expression", function()
		assert.equal("yes", sh('[ "$(echo foo)" = foo ] && echo yes'))
	end)
end)
