-- SPDX-License-Identifier: ISC
-- sh/compound_multiline_test.lua: tests for multiline compound commands

local unistd = require("posix.unistd")
local wait = require("posix.sys.wait")
local fcntl = require("posix.fcntl")

local function sh_script(script)
	local src = debug.getinfo(1, "S").source:match("^@(.+/)")
	local tmp = os.tmpname()
	local f = io.open(tmp, "w")
	f:write(script)
	f:close()
	local cmd = string.format("lua5.4 %ssh.lua %s 2>/dev/null", src, tmp)
	local p = io.popen(cmd)
	local out = p:read("*a"):gsub("\n$", "")
	p:close()
	os.remove(tmp)
	return out
end

describe("multiline compound commands", function()
	describe("if/then/fi", function()
		it("works across newlines", function()
			assert.equal(
				"yes",
				sh_script([[
if true
then
  echo yes
fi
]])
			)
		end)

		it("else across newlines", function()
			assert.equal(
				"no",
				sh_script([[
if false
then
  echo yes
else
  echo no
fi
]])
			)
		end)

		it("elif across newlines", function()
			assert.equal(
				"two",
				sh_script([[
if false
then
  echo one
elif true
then
  echo two
else
  echo three
fi
]])
			)
		end)
	end)

	describe("while/do/done", function()
		it("works across newlines", function()
			assert.equal(
				"3\n2\n1",
				sh_script([[
x=3
while [ $x -gt 0 ]
do
  echo $x
  x=$(expr $x - 1)
done
]])
			)
		end)
	end)

	describe("until/do/done", function()
		it("works across newlines", function()
			assert.equal(
				"0\n1\n2",
				sh_script([[
x=0
until [ $x -eq 3 ]
do
  echo $x
  x=$(expr $x + 1)
done
]])
			)
		end)
	end)

	describe("for/in/do/done", function()
		it("works across newlines", function()
			assert.equal(
				"a\nb\nc",
				sh_script([[
for i in a b c
do
  echo $i
done
]])
			)
		end)
	end)

	describe("nested all structures", function()
		it("nests if inside for inside while", function()
			assert.equal(
				"1:odd\n2:even\n3:odd",
				sh_script([[
x=1
while [ $x -le 3 ]
do
  for parity in odd even
  do
    if [ $parity = odd ]
    then
      if [ $(expr $x % 2) -eq 1 ]
      then
        echo $x:odd
      fi
    else
      if [ $(expr $x % 2) -eq 0 ]
      then
        echo $x:even
      fi
    fi
  done
  x=$(expr $x + 1)
done
]])
			)
		end)
	end)
end)
