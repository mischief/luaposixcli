-- SPDX-License-Identifier: ISC
-- sh/redir_test.lua: tests for I/O redirection

local unistd = require("posix.unistd")

local function sh(input)
	local src = debug.getinfo(1, "S").source:match("^@(.+/)")
	local cmd = string.format("lua5.4 %ssh.lua -c '%s' 2>/dev/null", src, input)
	local f = io.popen(cmd)
	local out = f:read("*a"):gsub("\n$", "")
	f:close()
	return out
end

local function tmpfile()
	local name = os.tmpname()
	return name
end

local function readfile(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local data = f:read("*a")
	f:close()
	return data
end

describe("redirection", function()
	describe("> output", function()
		it("redirects stdout to file", function()
			local tmp = tmpfile()
			sh("echo hello > " .. tmp)
			assert.equal("hello\n", readfile(tmp))
			os.remove(tmp)
		end)

		it("creates file if not exists", function()
			local tmp = tmpfile()
			os.remove(tmp)
			sh("echo new > " .. tmp)
			assert.equal("new\n", readfile(tmp))
			os.remove(tmp)
		end)

		it("truncates existing file", function()
			local tmp = tmpfile()
			local f = io.open(tmp, "w")
			f:write("old content\n")
			f:close()
			sh("echo replaced > " .. tmp)
			assert.equal("replaced\n", readfile(tmp))
			os.remove(tmp)
		end)
	end)

	describe(">> append", function()
		it("appends to file", function()
			local tmp = tmpfile()
			local f = io.open(tmp, "w")
			f:write("first\n")
			f:close()
			sh("echo second >> " .. tmp)
			assert.equal("first\nsecond\n", readfile(tmp))
			os.remove(tmp)
		end)

		it("creates file if not exists", function()
			local tmp = tmpfile()
			os.remove(tmp)
			sh("echo appended >> " .. tmp)
			assert.equal("appended\n", readfile(tmp))
			os.remove(tmp)
		end)
	end)

	describe("< input", function()
		it("redirects stdin from file", function()
			local tmp = tmpfile()
			local f = io.open(tmp, "w")
			f:write("from file\n")
			f:close()
			assert.equal("from file", sh("cat < " .. tmp))
			os.remove(tmp)
		end)
	end)

	describe("2> stderr", function()
		it("redirects stderr to file", function()
			local tmp = tmpfile()
			-- ls on nonexistent file writes to stderr
			local src = debug.getinfo(1, "S").source:match("^@(.+/)")
			local cmd = string.format("lua5.4 %ssh.lua -c 'ls /nonexistent_xyz_42 2>%s'", src, tmp)
			os.execute(cmd)
			local content = readfile(tmp)
			assert.is_truthy(content and content:find("nonexistent"))
			os.remove(tmp)
		end)
	end)

	describe("combined", function()
		it("redirection does not appear in args", function()
			local tmp = tmpfile()
			sh("echo hello world > " .. tmp)
			assert.equal("hello world\n", readfile(tmp))
			os.remove(tmp)
		end)
	end)
end)
