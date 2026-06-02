-- SPDX-License-Identifier: ISC
local notposix = require("luaposixcli.sys")

describe("notposix", function()

	describe("priority", function()
		it("has constants", function()
			assert.is_number(notposix.PRIO_PROCESS)
			assert.is_number(notposix.PRIO_PGRP)
			assert.is_number(notposix.PRIO_USER)
		end)

		it("getpriority returns a number", function()
			local prio = notposix.getpriority(notposix.PRIO_PROCESS, 0)
			assert.is_number(prio)
		end)

		it("setpriority with 0 increment succeeds", function()
			local cur = notposix.getpriority(notposix.PRIO_PROCESS, 0)
			local ok = notposix.setpriority(notposix.PRIO_PROCESS, 0, cur)
			assert.equal(0, ok)
		end)
	end)

	describe("environ", function()
		it("returns a table", function()
			local env = notposix.environ()
			assert.is_table(env)
			assert.is_true(#env > 0)
		end)

		it("entries are KEY=VALUE strings", function()
			local env = notposix.environ()
			for _, entry in ipairs(env) do
				assert.is_string(entry)
				assert.is_truthy(entry:find("="))
				break
			end
		end)

		it("contains PATH", function()
			local env = notposix.environ()
			local found = false
			for _, entry in ipairs(env) do
				if entry:match("^PATH=") then found = true; break end
			end
			assert.is_true(found)
		end)
	end)

	describe("regex", function()
		it("has constants", function()
			assert.is_number(notposix.REG_EXTENDED)
			assert.is_number(notposix.REG_ICASE)
			assert.is_number(notposix.REG_NOSUB)
			assert.is_number(notposix.REG_NEWLINE)
		end)

		it("regmatch matches BRE", function()
			assert.is_true(notposix.regmatch("hel.*", "hello", 0))
			assert.is_false(notposix.regmatch("^world", "hello", 0))
		end)

		it("regmatch matches ERE", function()
			assert.is_true(notposix.regmatch("hel+o", "hello", notposix.REG_EXTENDED))
			assert.is_false(notposix.regmatch("hel+o", "hello", 0)) -- BRE: + is literal
		end)

		it("regmatch case insensitive", function()
			assert.is_true(notposix.regmatch("hello", "HELLO", notposix.REG_ICASE))
		end)

		it("regcomp returns userdata", function()
			local re = notposix.regcomp("hello", notposix.REG_EXTENDED)
			assert.is_userdata(re)
		end)

		it("regcomp returns nil on bad pattern", function()
			local re, err = notposix.regcomp("[invalid", notposix.REG_EXTENDED)
			assert.is_nil(re)
			assert.is_string(err)
		end)

		it("exec returns match offsets", function()
			local re = notposix.regcomp("(h)(ello)", notposix.REG_EXTENDED)
			local m = re:exec("hello world")
			assert.is_table(m)
			assert.equal(1, m[1][1])  -- full match start
			assert.equal(5, m[1][2])  -- full match end
			assert.equal(1, m[2][1])  -- group 1 start
			assert.equal(1, m[2][2])  -- group 1 end
			assert.equal(2, m[3][1])  -- group 2 start
			assert.equal(5, m[3][2])  -- group 2 end
		end)

		it("exec returns false on no match", function()
			local re = notposix.regcomp("xyz", notposix.REG_EXTENDED)
			assert.is_false(re:exec("hello"))
		end)

		it("gc frees regex without error", function()
			for i = 1, 100 do
				notposix.regcomp("test" .. i, notposix.REG_EXTENDED)
			end
			collectgarbage()
		end)
	end)

end)
