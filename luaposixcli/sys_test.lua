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

	-- The rest of this module is the privileged corner. What a user
	-- namespace cannot reach is in sys_priv_test.sh; what needs no
	-- privilege at all is run here, because a binding nothing ever calls
	-- is a binding nobody knows is wrong.

	describe("device numbers", function()
		it("splits the number a stat gives back", function()
			local st = require("posix.sys.stat").stat("/dev/null")
			assert.is_table(st)
			-- /dev/null is 1:3 on every Linux
			assert.equal(1, notposix.major(st.st_rdev))
			assert.equal(3, notposix.minor(st.st_rdev))
		end)

		it("mknod makes a fifo, which needs no privilege", function()
			local stat = require("posix.sys.stat")
			local path = os.tmpname()
			os.remove(path)
			local ok = notposix.mknod(path, stat.S_IFIFO | tonumber("600", 8))
			assert.equal(0, ok)
			local st = stat.stat(path)
			assert.is_table(st)
			assert.is_true(stat.S_ISFIFO(st.st_mode) ~= 0)
			os.remove(path)
		end)

		it("mknod says why when it cannot", function()
			local stat = require("posix.sys.stat")
			local ok, err = notposix.mknod("/proc/nothing/here",
				stat.S_IFIFO | tonumber("600", 8))
			assert.is_nil(ok)
			assert.is_string(err)
		end)
	end)

	describe("flock", function()
		it("takes and releases an exclusive lock", function()
			local fcntl = require("posix.fcntl")
			local unistd = require("posix.unistd")
			local path = os.tmpname()
			local fd = fcntl.open(path, fcntl.O_RDWR)
			assert.is_number(fd)

			assert.equal(0, notposix.flock(fd, notposix.LOCK_EX))

			-- a second descriptor on the same file cannot have it, and
			-- LOCK_NB is what turns that into an answer rather than a wait
			local other = fcntl.open(path, fcntl.O_RDWR)
			local ok, err = notposix.flock(other, notposix.LOCK_EX | notposix.LOCK_NB)
			assert.is_nil(ok)
			assert.is_string(err)

			assert.equal(0, notposix.flock(fd, notposix.LOCK_UN))
			assert.equal(0, notposix.flock(other, notposix.LOCK_EX | notposix.LOCK_NB))

			unistd.close(fd)
			unistd.close(other)
			os.remove(path)
		end)
	end)

	describe("ioctl", function()
		it("refuses a buffer size that is not one", function()
			assert.has_error(function() notposix.ioctlbuf(0, 0, 0) end)
			assert.has_error(function() notposix.ioctlbuf(0, 0, 1 << 20) end)
		end)

		it("gives back a buffer the same size it was handed", function()
			-- a descriptor that is not a terminal fails, and the failure
			-- is the reason rather than a crash
			local ok, err = notposix.ioctlbuf(0, notposix.RTC_RD_TIME or 0x80247009, 36)
			if ok then
				assert.equal(36, #ok)
			else
				assert.is_string(err)
			end
		end)
	end)

	describe("shadow", function()
		it("answers about a user nobody has", function()
			local entry, err = notposix.getspnam("no_such_user_at_all")
			assert.is_nil(entry)
			assert.is_string(err)
		end)
	end)

end)
