-- SPDX-License-Identifier: ISC
-- sh/prefix_assign_test.lua: tests for prefix variable assignments (VAR=val cmd)

local function sh(input)
	local src = debug.getinfo(1, "S").source:match("^@(.+/)") or "./"
	local cmd = string.format("lua5.4 %ssh.lua -c '%s' 2>/dev/null", src, input)
	local f = io.popen(cmd)
	local out = f:read("*a"):gsub("\n$", "")
	f:close()
	return out
end

describe("prefix variable assignments", function()
	it("passes variable to external command environment", function()
		-- env prints its environment; grep for the specific var
		assert.equal("hello", sh("TESTVAR=hello env | grep TESTVAR= | sed s/TESTVAR=//"))
	end)

	it("multiple prefix assignments all reach the command", function()
		assert.equal("A=1\nB=2", sh("A=1 B=2 env | grep -e ^A= -e ^B= | sort"))
	end)

	it("does not persist prefix assignment in shell after command", function()
		assert.equal("", sh("X=foo env > /dev/null; echo ${X}"))
	end)

	it("prefix assignment overrides existing variable for child only", function()
		assert.equal("override\noriginal", sh("X=original; X=override env | grep ^X= | sed s/X=//; echo $X"))
	end)

	it("${var} in args expands from shell env, not prefix (POSIX expansion order)", function()
		-- X is unset in shell; prefix X=hello only goes to child env
		-- so echo ${X} expands to empty string before exec
		assert.equal("", sh("X=hello echo ${X}"))
	end)

	it("pure assignment still sets variable in shell", function()
		assert.equal("42", sh("MYVAR=42; echo $MYVAR"))
	end)
end)
