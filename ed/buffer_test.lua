-- SPDX-License-Identifier: ISC
-- ed/buffer_test.lua - busted tests for the ed buffer engine
local buffer = require("ed.buffer")

describe("buffer.new", function()
	it("creates an empty buffer", function()
		local b = buffer.new()
		assert.equals(0, #b.lines)
		assert.equals(0, b.cur)
		assert.is_false(b.dirty)
	end)
end)

describe("buffer:load", function()
	it("loads a file", function()
		local tmp = os.tmpname()
		local f = io.open(tmp, "w")
		f:write("hello\nworld\n")
		f:close()
		local b = buffer.new()
		local ok, count = b:load(tmp)
		assert.is_true(ok)
		assert.equals(2, count)
		assert.equals("hello", b.lines[1])
		assert.equals("world", b.lines[2])
		assert.equals(2, b.cur)
		os.remove(tmp)
	end)

	it("returns error for missing file", function()
		local b = buffer.new()
		local ok, err = b:load("/nonexistent_file_xyz")
		assert.is_false(ok)
		assert.truthy(err:find("No such file"))
	end)
end)

describe("buffer:write", function()
	it("writes buffer to file", function()
		local b = buffer.new()
		b.lines = { "alpha", "beta", "gamma" }
		local tmp = os.tmpname()
		local ok, bytes = b:write(tmp)
		assert.is_true(ok)
		assert.equals(17, bytes) -- "alpha\nbeta\ngamma\n"
		local f = io.open(tmp, "r")
		assert.equals("alpha\nbeta\ngamma\n", f:read("a"))
		f:close()
		os.remove(tmp)
	end)

	it("writes a range", function()
		local b = buffer.new()
		b.lines = { "a", "b", "c" }
		local tmp = os.tmpname()
		b:write(tmp, 2, 3)
		local f = io.open(tmp, "r")
		assert.equals("b\nc\n", f:read("a"))
		f:close()
		os.remove(tmp)
	end)
end)

describe("buffer:parse_addr", function()
	it("parses numeric address", function()
		local b = buffer.new()
		b.lines = { "a", "b", "c" }
		b.cur = 2
		local addr, pos = b:parse_addr("3p")
		assert.equals(3, addr)
		assert.equals(2, pos)
	end)

	it("parses dot (current line)", function()
		local b = buffer.new()
		b.lines = { "a", "b", "c" }
		b.cur = 2
		local addr = b:parse_addr(".")
		assert.equals(2, addr)
	end)

	it("parses dollar (last line)", function()
		local b = buffer.new()
		b.lines = { "a", "b", "c" }
		local addr = b:parse_addr("$")
		assert.equals(3, addr)
	end)

	it("parses forward search", function()
		local b = buffer.new()
		b.lines = { "foo", "bar", "baz" }
		b.cur = 1
		local addr = b:parse_addr("/bar/")
		assert.equals(2, addr)
	end)

	it("parses backward search", function()
		local b = buffer.new()
		b.lines = { "foo", "bar", "baz" }
		b.cur = 3
		local addr = b:parse_addr("?foo?")
		assert.equals(1, addr)
	end)

	it("parses address with offset", function()
		local b = buffer.new()
		b.lines = { "a", "b", "c", "d" }
		b.cur = 1
		local addr = b:parse_addr("2+1")
		assert.equals(3, addr)
	end)
end)

describe("buffer:parse_range", function()
	it("parses single address", function()
		local b = buffer.new()
		b.lines = { "a", "b", "c" }
		local a1, a2, cmd = b:parse_range("2p")
		assert.equals(2, a1)
		assert.equals(2, a2)
		assert.equals("p", cmd)
	end)

	it("parses comma range", function()
		local b = buffer.new()
		b.lines = { "a", "b", "c" }
		local a1, a2, cmd = b:parse_range("1,3p")
		assert.equals(1, a1)
		assert.equals(3, a2)
		assert.equals("p", cmd)
	end)

	it("parses % as 1,$", function()
		local b = buffer.new()
		b.lines = { "a", "b", "c" }
		local a1, a2, cmd = b:parse_range("%p")
		assert.equals(1, a1)
		assert.equals(3, a2)
		assert.equals("p", cmd)
	end)
end)

describe("buffer:exec commands", function()
	it("appends lines", function()
		local b = buffer.new()
		-- Simulate input
		local old_read = io.read
		local input = { "hello", "world", "." }
		local idx = 0
		io.read = function() idx = idx + 1; return input[idx] end
		b:exec("a")
		io.read = old_read
		assert.equals(2, #b.lines)
		assert.equals("hello", b.lines[1])
		assert.equals("world", b.lines[2])
		assert.equals(2, b.cur)
	end)

	it("inserts lines", function()
		local b = buffer.new()
		b.lines = { "existing" }
		b.cur = 1
		local old_read = io.read
		local input = { "new", "." }
		local idx = 0
		io.read = function() idx = idx + 1; return input[idx] end
		b:exec("1i")
		io.read = old_read
		assert.equals(2, #b.lines)
		assert.equals("new", b.lines[1])
		assert.equals("existing", b.lines[2])
	end)

	it("deletes lines", function()
		local b = buffer.new()
		b.lines = { "a", "b", "c" }
		b.cur = 1
		b:exec("2d")
		assert.equals(2, #b.lines)
		assert.equals("a", b.lines[1])
		assert.equals("c", b.lines[2])
	end)

	it("substitutes", function()
		local b = buffer.new()
		b.lines = { "hello world" }
		b.cur = 1
		b:exec("1s/world/earth/")
		assert.equals("hello earth", b.lines[1])
	end)

	it("global substitute", function()
		local b = buffer.new()
		b.lines = { "aaa" }
		b.cur = 1
		b:exec("1s/a/b/g")
		assert.equals("bbb", b.lines[1])
	end)

	it("joins lines", function()
		local b = buffer.new()
		b.lines = { "hello", " world" }
		b.cur = 1
		b:exec("1,2j")
		assert.equals(1, #b.lines)
		assert.equals("hello world", b.lines[1])
	end)

	it("prints line count with =", function()
		local b = buffer.new()
		b.lines = { "a", "b", "c" }
		local output = {}
		local old_write = io.write
		io.write = function(s) output[#output + 1] = s end
		b:exec("=")
		io.write = old_write
		assert.equals("3\n", table.concat(output))
	end)

	it("sets mark with k", function()
		local b = buffer.new()
		b.lines = { "a", "b", "c" }
		b.cur = 2
		b:exec("2ka")
		assert.equals(2, b.marks["a"])
	end)

	it("navigates to mark", function()
		local b = buffer.new()
		b.lines = { "a", "b", "c" }
		b.marks["x"] = 3
		local addr = b:parse_addr("'x")
		assert.equals(3, addr)
	end)

	it("quit returns nil", function()
		local b = buffer.new()
		assert.is_nil(b:exec("Q"))
	end)

	it("dirty quit warns then quits", function()
		local b = buffer.new()
		b.lines = { "a" }
		b.dirty = true
		-- First q warns
		local r = b:exec("q")
		assert.is_false(r)
		-- Second q quits
		r = b:exec("q")
		assert.is_nil(r)
	end)

	it("rejects ex commands in ed mode", function()
		local b = buffer.new({ ex_mode = false })
		b.lines = { "a", "b", "c" }
		b.cur = 1
		local r = b:exec("3m0")
		assert.is_false(r)
	end)

	it("accepts move in ex mode", function()
		local b = buffer.new({ ex_mode = true })
		b.lines = { "a", "b", "c" }
		b.cur = 1
		b:exec("3m0")
		assert.equals("c", b.lines[1])
		assert.equals("a", b.lines[2])
	end)

	it("accepts copy in ex mode", function()
		local b = buffer.new({ ex_mode = true })
		b.lines = { "a", "b", "c" }
		b.cur = 1
		b:exec("1t3")
		assert.equals(4, #b.lines)
		assert.equals("a", b.lines[4])
	end)
end)

describe("buffer:exec global", function()
	it("g/pat/d deletes matching lines", function()
		local b = buffer.new()
		b.lines = { "foo", "bar", "foo2", "baz" }
		b.cur = 1
		b:exec("g/foo/d")
		assert.equals(2, #b.lines)
		assert.equals("bar", b.lines[1])
		assert.equals("baz", b.lines[2])
	end)

	it("v/pat/d deletes non-matching lines", function()
		local b = buffer.new()
		b.lines = { "foo", "bar", "foo2", "baz" }
		b.cur = 1
		b:exec("v/foo/d")
		assert.equals(2, #b.lines)
		assert.equals("foo", b.lines[1])
		assert.equals("foo2", b.lines[2])
	end)
end)
