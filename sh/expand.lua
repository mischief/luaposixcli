-- SPDX-License-Identifier: ISC
-- sh/expand.lua: word expansion (variable + command substitution)
local lpeg = require("lpeg")
local P, S, C, Ct, Cmt = lpeg.P, lpeg.S, lpeg.C, lpeg.Ct, lpeg.Cmt

local env = require("sh.env")

local special = lpeg.S("?$!-@*#0")
local namechar = lpeg.R("az", "AZ", "09") + P("_")
local namefirst = lpeg.R("az", "AZ") + P("_")
local varname = namefirst * namechar ^ 0

local function lookup(name)
	return env.get(name) or ""
end

-- find the shell path for command substitution
local sh_path

local function set_sh_path(path)
	sh_path = path
end

local unistd = require("posix.unistd")
local wait = require("posix.sys.wait")

-- callback to execute a command string in the current shell
-- set by sh.lua at startup via set_run_fn
local run_fn = nil

local function set_run_fn(fn)
	run_fn = fn
end

local function cmdsub(cmd)
	local r, w = unistd.pipe()
	local pid = unistd.fork()
	if pid == 0 then
		-- child (subshell): redirect stdout to pipe, run command, exit
		unistd.close(r)
		unistd.dup2(w, 1)
		unistd.close(w)
		if run_fn then
			run_fn(cmd)
		end
		os.exit(tonumber(env.get("?")) or 0)
	end
	-- parent: read from pipe
	unistd.close(w)
	local chunks = {}
	while true do
		local data = unistd.read(r, 4096)
		if not data or data == "" then
			break
		end
		chunks[#chunks + 1] = data
	end
	unistd.close(r)
	wait.wait(pid)
	local out = table.concat(chunks)
	-- strip trailing newlines per POSIX
	return (out:gsub("\n+$", ""))
end

-- match $(...) using Cmt with a P("$") guard so it never matches empty
-- Evaluate arithmetic expression (POSIX shell arithmetic)
local function arith_eval(expr)
	-- Expand variables in the expression
	local expanded = expr:gsub("%$([%a_][%w_]*)", function(name)
		return env.get(name) or "0"
	end):gsub("%$(%d)", function(n)
		return env.get(n) or "0"
	end)
	-- Replace variable names (bare words) with their values
	expanded = expanded:gsub("([%a_][%w_]*)", function(name)
		local v = env.get(name)
		return v and v or name
	end)
	-- Evaluate using Lua (safe subset: only arithmetic)
	-- Convert shell operators: ! → not, ~ is bitwise not (lua 5.4 supports it)
	expanded = expanded:gsub("([^!<>=])!=", "%1~=") -- != → ~=
	expanded = expanded:gsub("^!=", "~=")
	expanded = expanded:gsub("&&", " and ")
	expanded = expanded:gsub("||", " or ")
	expanded = expanded:gsub("([^~])!", "%1 not ")
	expanded = expanded:gsub("^!", "not ")
	local fn, err = load("return (" .. expanded .. ")", "arith", "t", { math = math })
	if fn then
		local ok, result = pcall(fn)
		if ok then
			if type(result) == "boolean" then return result and "1" or "0" end
			if type(result) == "number" then return tostring(math.floor(result)) end
			return tostring(result)
		end
	end
	return "0"
end

local cmdsub_pat = Cmt(P("$"), function(s, p)
	-- p is after the "$", check for "("
	if s:sub(p, p) ~= "(" then
		return nil
	end
	-- Check for $(( — arithmetic expansion
	if s:sub(p, p + 1) == "((" then
		-- Find matching ))
		local depth = 0
		local i = p + 1 -- at the second (
		while i <= #s do
			local c = s:sub(i, i)
			if c == "(" then depth = depth + 1
			elseif c == ")" then
				depth = depth - 1
				if depth == 0 and s:sub(i, i + 1) == "))" then
					local inner = s:sub(p + 2, i - 1)
					return i + 2, arith_eval(inner)
				end
			end
			i = i + 1
		end
		return nil
	end
	-- Regular command substitution $(...)
	local depth = 0
	local i = p -- at the '('
	while i <= #s do
		local c = s:sub(i, i)
		if c == "(" then
			depth = depth + 1
		elseif c == ")" then
			depth = depth - 1
			if depth == 0 then
				local inner = s:sub(p + 1, i - 1)
				return i + 1, cmdsub(inner)
			end
		end
		i = i + 1
	end
	return nil
end)

-- We need to try cmdsub before dollar_exp since both start with $
-- Rebuild patterns with cmdsub support

-- ${#var} string length
local function lookup_length(name)
	local val = env.get(name) or ""
	return tostring(#val)
end

-- Shell pattern matching for ${var%pat}, ${var#pat} etc.
local function sh_pattern_to_lua(pat)
	local res = ""
	local i = 1
	while i <= #pat do
		local c = pat:sub(i, i)
		if c == "*" then res = res .. ".*"
		elseif c == "?" then res = res .. "."
		elseif c == "[" then
			local j = pat:find("]", i + 1, true)
			if j then
				res = res .. pat:sub(i, j)
				i = j
			else
				res = res .. "%["
			end
		elseif c:match("[%(%)%.%%%+%-%^%$]") then
			res = res .. "%" .. c
		else
			res = res .. c
		end
		i = i + 1
	end
	return res
end

-- Find matching } handling nested ${}, $(), quotes
local function find_closing_brace(s, start)
	local depth = 1
	local i = start
	while i <= #s do
		local c = s:sub(i, i)
		if c == "}" then
			depth = depth - 1
			if depth == 0 then return i end
		elseif c == "$" and s:sub(i + 1, i + 1) == "{" then
			depth = depth + 1
			i = i + 1
		elseif c == "$" and s:sub(i + 1, i + 1) == "(" then
			-- skip nested $()
			local d = 1
			i = i + 2
			while i <= #s and d > 0 do
				if s:sub(i, i) == "(" then d = d + 1
				elseif s:sub(i, i) == ")" then d = d - 1 end
				i = i + 1
			end
			i = i - 1
		elseif c == "'" then
			i = i + 1
			while i <= #s and s:sub(i, i) ~= "'" do i = i + 1 end
		elseif c == '"' then
			i = i + 1
			while i <= #s do
				local dc = s:sub(i, i)
				if dc == '"' then break end
				if dc == "\\" then i = i + 1 end
				i = i + 1
			end
		elseif c == "\\" then
			i = i + 1
		end
		i = i + 1
	end
	return nil
end

-- forward declaration for recursive expansion
local word

-- Match-time capture for complex ${...} expansions
local brace_exp = Cmt(P("${"), function(s, p)
	-- p is after "${"
	-- Handle ${#var}
	if s:sub(p, p) == "#" then
		local name = s:match("^([%a_][%w_]*)", p + 1)
		if name and s:sub(p + 1 + #name, p + 1 + #name) == "}" then
			local val = env.get(name) or ""
			return p + 2 + #name, tostring(#val)
		end
	end

	-- Find the variable name (or special param)
	local name, nend
	name = s:match("^([%a_][%w_]*)", p)
	if name then
		nend = p + #name
	else
		-- special parameter or positional
		local sp = s:match("^([%?%$!%-@*#0])", p)
		if sp then
			name = sp
			nend = p + 1
		else
			local digits = s:match("^(%d+)", p)
			if digits then
				name = digits
				nend = p + #digits
			else
				return nil
			end
		end
	end

	-- Simple ${VAR}
	if s:sub(nend, nend) == "}" then
		return nend + 1, lookup(name)
	end

	-- Determine operator
	local op
	local two = s:sub(nend, nend + 1)
	if two == ":-" or two == ":=" or two == ":?" or two == ":+" then
		op = two
		nend = nend + 2
	elseif two == "%%" or two == "##" then
		op = two
		nend = nend + 2
	else
		local one = s:sub(nend, nend)
		if one == "-" or one == "=" or one == "?" or one == "+" or one == "%" or one == "#" then
			op = one
			nend = nend + 1
		else
			return nil
		end
	end

	-- Find matching closing brace
	local brace_end = find_closing_brace(s, nend)
	if not brace_end then return nil end

	local word_str = s:sub(nend, brace_end - 1)
	local val = env.get(name)

	if op == ":-" then
		if val == nil or val == "" then return brace_end + 1, word(word_str) end
		return brace_end + 1, val
	elseif op == "-" then
		if val == nil then return brace_end + 1, word(word_str) end
		return brace_end + 1, val
	elseif op == ":=" then
		if val == nil or val == "" then
			local expanded = word(word_str)
			env.set(name, expanded)
			return brace_end + 1, expanded
		end
		return brace_end + 1, val
	elseif op == "=" then
		if val == nil then
			local expanded = word(word_str)
			env.set(name, expanded)
			return brace_end + 1, expanded
		end
		return brace_end + 1, val
	elseif op == ":?" then
		if val == nil or val == "" then
			local msg = word_str ~= "" and word(word_str) or (name .. ": parameter null or not set")
			require("posix.unistd").write(2, "sh: " .. name .. ": " .. msg .. "\n")
			return brace_end + 1, ""
		end
		return brace_end + 1, val
	elseif op == "?" then
		if val == nil then
			local msg = word_str ~= "" and word(word_str) or (name .. ": parameter not set")
			require("posix.unistd").write(2, "sh: " .. name .. ": " .. msg .. "\n")
			return brace_end + 1, ""
		end
		return brace_end + 1, val
	elseif op == ":+" then
		if val ~= nil and val ~= "" then return brace_end + 1, word(word_str) end
		return brace_end + 1, ""
	elseif op == "+" then
		if val ~= nil then return brace_end + 1, word(word_str) end
		return brace_end + 1, ""
	elseif op == "%%" then
		val = val or ""
		local pat = sh_pattern_to_lua(word(word_str))
		-- largest suffix: try removing from position 1..#val
		for i = 1, #val do
			if val:sub(i):match("^" .. pat .. "$") then
				return brace_end + 1, val:sub(1, i - 1)
			end
		end
		return brace_end + 1, val
	elseif op == "%" then
		val = val or ""
		local pat = sh_pattern_to_lua(word(word_str))
		-- smallest suffix: try removing from end
		for i = #val, 1, -1 do
			if val:sub(i):match("^" .. pat .. "$") then
				return brace_end + 1, val:sub(1, i - 1)
			end
		end
		return brace_end + 1, val
	elseif op == "##" then
		val = val or ""
		local pat = sh_pattern_to_lua(word(word_str))
		-- largest prefix: try from longest
		for i = #val, 1, -1 do
			if val:sub(1, i):match("^" .. pat .. "$") then
				return brace_end + 1, val:sub(i + 1)
			end
		end
		return brace_end + 1, val
	elseif op == "#" then
		val = val or ""
		local pat = sh_pattern_to_lua(word(word_str))
		-- smallest prefix
		for i = 1, #val do
			if val:sub(1, i):match("^" .. pat .. "$") then
				return brace_end + 1, val:sub(i + 1)
			end
		end
		return brace_end + 1, val
	end
	return nil
end)

-- $VAR, $?, $1, etc. (simple forms without braces)
local dollar_simple =
	(P("$") * C(special)) / lookup +
	(P("$") * C(lpeg.R("09"))) / lookup +
	(P("$") * C(varname)) / lookup

-- Combined dollar expansion: try brace_exp first, then simple
local dollar_exp = brace_exp + dollar_simple

-- single-quoted: literal (no expansion)
local sq_lit = P("'") * C((1 - P("'")) ^ 0) * P("'")

-- double-quoted: expand $(...) and $VAR inside, handle \" \\ \$ \` escapes
local dq_escape = P("\\") * C(S('"\\$`')) + P("\\") * C(P(1)) / "\\%1"
local dq_piece = cmdsub_pat + dollar_exp + dq_escape + C(1 - P('"') - P("\\"))
local dq_lit = P('"') * Ct(dq_piece ^ 0) * P('"') / table.concat

-- unquoted piece
local unquoted = cmdsub_pat + dollar_exp + C(1 - lpeg.S("'\""))

-- full word
local word_pat = Ct((sq_lit + dq_lit + unquoted) ^ 0) / table.concat

word = function(s)
	return lpeg.match(word_pat, s) or s
end

-- detect NAME=value
local assign_pat = C(namefirst * namechar ^ 0) * P("=") * C(P(1) ^ 0)

local function is_assignment(s)
	return lpeg.match(assign_pat, s) ~= nil
end

local function parse_assignment(s)
	local name, val = lpeg.match(assign_pat, s)
	return name, val
end

-- Check if a raw token (before quote removal) contains unquoted glob metacharacters
local glob_meta = S("*?[")
local function has_unquoted_glob(s)
	local i = 1
	while i <= #s do
		local c = s:sub(i, i)
		if c == "'" then
			-- skip single-quoted section
			local j = s:find("'", i + 1, true)
			if j then i = j + 1 else i = i + 1 end
		elseif c == '"' then
			-- skip double-quoted section (respecting \")
			i = i + 1
			while i <= #s do
				local dc = s:sub(i, i)
				if dc == '"' then i = i + 1; break end
				if dc == "\\" then i = i + 2 else i = i + 1 end
			end
		elseif c == "\\" then
			i = i + 2 -- escaped char, skip
		elseif c == "*" or c == "?" or c == "[" then
			return true
		else
			i = i + 1
		end
	end
	return false
end

-- Expand a word with variable/command substitution, then glob-expand if applicable.
-- Returns a list of words (may be more than one if glob matches).
local posix_glob = require("posix.glob")
local function glob_word(s)
	if not has_unquoted_glob(s) then
		return { word(s) }
	end
	-- Expand variables first, but preserve glob chars
	local expanded = word(s)
	-- Try glob
	local matches = posix_glob.glob(expanded, 0)
	if matches then
		table.sort(matches)
		return matches
	end
	-- No matches: return literal (POSIX behavior)
	return { expanded }
end

return {
	word = word,
	glob_word = glob_word,
	is_assignment = is_assignment,
	parse_assignment = parse_assignment,
	set_sh_path = set_sh_path,
	set_run_fn = set_run_fn,
	get_run_fn = function() return run_fn end,
}
