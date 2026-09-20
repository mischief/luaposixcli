-- SPDX-License-Identifier: ISC
-- luaposixcli/util_test.lua
local util = require("luaposixcli.util")

describe("luaposixcli.util", function()
	it("basename strips directories", function()
		assert.equal("gzip", util.basename("/usr/bin/gzip"))
		assert.equal("gzip", util.basename("gzip"))
		assert.equal("", util.basename(""))
	end)

	it("slurp reads a whole file", function()
		local path = os.tmpname()
		local f = assert(io.open(path, "wb"))
		f:write("one\ntwo\n")
		f:close()
		assert.equal("one\ntwo\n", util.slurp(path))
		os.remove(path)
	end)

	it("slurp reports a missing file", function()
		local data, err = util.slurp("/nonexistent/for/sure")
		assert.is_nil(data)
		assert.is_string(err)
	end)

	it("lines keeps blank lines", function()
		local out = {}
		for line in util.lines("a\n\nb\n") do out[#out + 1] = line end
		assert.same({ "a", "", "b" }, out)
	end)

	it("lines can keep the newline, and a last line without one", function()
		local out = {}
		for line in util.lines("a\nb", true) do out[#out + 1] = line end
		assert.same({ "a\n", "b" }, out)
	end)
end)
