-- SPDX-License-Identifier: ISC
-- sh/test.lua: POSIX test / [ builtin
local stat = require("posix.sys.stat")
local unistd = require("posix.unistd")

local function fstat(p)
	return stat.stat(p)
end

local file_ops = {
	["-e"] = function(p)
		return fstat(p) ~= nil
	end,
	["-f"] = function(p)
		local s = fstat(p)
		return s ~= nil and stat.S_ISREG(s.st_mode) ~= 0
	end,
	["-d"] = function(p)
		local s = fstat(p)
		return s ~= nil and stat.S_ISDIR(s.st_mode) ~= 0
	end,
	["-b"] = function(p)
		local s = fstat(p)
		return s ~= nil and stat.S_ISBLK(s.st_mode) ~= 0
	end,
	["-c"] = function(p)
		local s = fstat(p)
		return s ~= nil and stat.S_ISCHR(s.st_mode) ~= 0
	end,
	["-p"] = function(p)
		local s = fstat(p)
		return s ~= nil and stat.S_ISFIFO(s.st_mode) ~= 0
	end,
	["-S"] = function(p)
		local s = fstat(p)
		return s ~= nil and stat.S_ISSOCK(s.st_mode) ~= 0
	end,
	["-L"] = function(p)
		local s = stat.lstat(p)
		return s ~= nil and stat.S_ISLNK(s.st_mode) ~= 0
	end,
	["-h"] = function(p)
		local s = stat.lstat(p)
		return s ~= nil and stat.S_ISLNK(s.st_mode) ~= 0
	end,
	["-s"] = function(p)
		local s = fstat(p)
		return s ~= nil and s.st_size > 0
	end,
	["-r"] = function(p)
		return unistd.access(p, "r") == 0
	end,
	["-w"] = function(p)
		return unistd.access(p, "w") == 0
	end,
	["-x"] = function(p)
		return unistd.access(p, "x") == 0
	end,
	["-t"] = function(fd)
		return unistd.isatty(tonumber(fd) or 1) == 1
	end,
}

local int_ops = {
	["-eq"] = function(a, b)
		return a == b
	end,
	["-ne"] = function(a, b)
		return a ~= b
	end,
	["-lt"] = function(a, b)
		return a < b
	end,
	["-le"] = function(a, b)
		return a <= b
	end,
	["-gt"] = function(a, b)
		return a > b
	end,
	["-ge"] = function(a, b)
		return a >= b
	end,
}

local function eval(args)
	-- strip trailing ] for [ form
	if args[#args] == "]" then
		local a = {}
		for i = 1, #args - 1 do
			a[i] = args[i]
		end
		args = a
	end

	local n = #args
	if n == 0 then
		return false
	end
	if n == 1 then
		return args[1] ~= ""
	end

	if n == 2 then
		if args[1] == "!" then
			return args[2] == ""
		end
		if args[1] == "-n" then
			return args[2] ~= ""
		end
		if args[1] == "-z" then
			return args[2] == ""
		end
		local f = file_ops[args[1]]
		if f then
			return f(args[2])
		end
		return false
	end

	if n == 3 then
		if args[1] == "!" then
			return not eval({ args[2], args[3] })
		end
		if args[2] == "=" then
			return args[1] == args[3]
		end
		if args[2] == "!=" then
			return args[1] ~= args[3]
		end
		local iop = int_ops[args[2]]
		if iop then
			return iop(tonumber(args[1]) or 0, tonumber(args[3]) or 0)
		end
		return false
	end

	if n == 4 and args[1] == "!" then
		return not eval({ args[2], args[3], args[4] })
	end

	return false
end

local function builtin(args)
	local a = {}
	for i = 2, #args do
		a[#a + 1] = args[i]
	end
	return eval(a) and 0 or 1
end

return { eval = eval, builtin = builtin }
