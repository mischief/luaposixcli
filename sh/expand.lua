-- SPDX-License-Identifier: ISC
-- sh/expand.lua: word expansion (variable + command substitution)
local lpeg = require("lpeg")
local P, S, C, Ct, Cmt = lpeg.P, lpeg.S, lpeg.C, lpeg.Ct, lpeg.Cmt

local env = require("sh.env")
local lexer = require("sh.lexer")
local unistd = require("posix.unistd")

local special = lpeg.S("?$!-@*#0")
local namechar = lpeg.R("az", "AZ", "09") + P("_")
local namefirst = lpeg.R("az", "AZ") + P("_")
local varname = namefirst * namechar ^ 0

local function lookup(name)
	return env.get(name) or ""
end

-- Report an expansion error. A non-interactive shell exits, as POSIX requires.
local function fatal(msg, status)
	unistd.write(2, "sh: " .. msg .. "\n")
	if not env.is_interactive() then
		env.run_exit_trap()
		os.exit(status or 2)
	end
end

-- find the shell path for command substitution
local sh_path

local function set_sh_path(path)
	sh_path = path
end

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

-- Arithmetic is evaluated after the rest of the word grammar is defined.
local arith_eval

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
	local e = lexer.skip_cmdsub(s, p)
	if not e then return nil end
	return e, cmdsub(s:sub(p + 1, e - 2))
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
		if c == "\\" and i < #pat then
			-- backslash makes the next character literal
			local nxt = pat:sub(i + 1, i + 1)
			res = res .. (nxt:match("%w") and nxt or ("%" .. nxt))
			i = i + 1
		elseif c == "*" then res = res .. ".*"
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
			local e = lexer.skip_cmdsub(s, i + 1)
			if not e then return nil end
			i = e - 1
		elseif c == "'" then
			i = i + 1
			while i <= #s and s:sub(i, i) ~= "'" do i = i + 1 end
		elseif c == '"' then
			local e = lexer.skip_dquote(s, i + 1)
			if not e then return nil end
			i = e - 1
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
	-- Handle ${#var}, including ${#0} and the other special parameters
	if s:sub(p, p) == "#" then
		local name = s:match("^([%a_][%w_]*)", p + 1)
			or s:match("^(%d+)", p + 1)
			or s:match("^([%?%$!%-@*])", p + 1)
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

	-- ${var:offset} and ${var:offset:length} (not POSIX, but widely used)
	if s:sub(nend, nend) == ":" and s:sub(nend + 1, nend + 1):match("[%d%s%$%(]") then
		local brace_end = find_closing_brace(s, nend + 1)
		if brace_end then
			local spec = s:sub(nend + 1, brace_end - 1)
			local off_str, len_str = spec:match("^([^:]*):(.*)$")
			if not off_str then off_str = spec end
			local off = tonumber(word(off_str))
			local len = len_str and tonumber(word(len_str))
			if off and (len_str == nil or len) then
				local val = env.get(name) or ""
				if off < 0 then off = math.max(#val + off, 0) end
				local first = off + 1
				local last = len and (first + len - 1) or #val
				if len and len < 0 then last = #val + len end
				return brace_end + 1, val:sub(first, last)
			end
		end
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
			local msg = word_str ~= "" and word(word_str) or "parameter null or not set"
			fatal(name .. ": " .. msg, 2)
			return brace_end + 1, ""
		end
		return brace_end + 1, val
	elseif op == "?" then
		if val == nil then
			local msg = word_str ~= "" and word(word_str) or "parameter not set"
			fatal(name .. ": " .. msg, 2)
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

-- here-document body with an unquoted delimiter: expansions happen as in a
-- double-quoted string, but a double quote is literal.
local hd_escape = P("\\") * C(S("\\$`"))
	+ P("\\") * P("\n") / ""
	+ P("\\") * C(P(1)) / "\\%1"
local hd_pat = Ct((cmdsub_pat + dollar_exp + hd_escape + C(1 - P("\\"))) ^ 0) / table.concat

local function heredoc(s)
	return lpeg.match(hd_pat, s) or s
end

-- full word
local word_pat = Ct((sq_lit + dq_lit + unquoted) ^ 0) / table.concat

word = function(s)
	return lpeg.match(word_pat, s) or s
end

-- POSIX shell arithmetic: signed integers with C operators and precedence.
-- Operands come from shell variables. Nothing here is executed as Lua code.
local function arith_fail(msg)
	error({ arith = msg }, 0)
end

local function arith_number(text)
	local n
	if text:match("^0[xX]%x+$") then
		n = tonumber(text)
	elseif text:match("^0%d+$") then
		n = tonumber(text:sub(2), 8)
	else
		n = tonumber(text, 10)
	end
	if not n or math.type(n) ~= "integer" then
		arith_fail("illegal number: " .. text)
	end
	return n
end

-- C truncation toward zero, not Lua's floor
local function arith_div(a, b)
	local q = a // b
	if q < 0 and q * b ~= a then q = q + 1 end
	return q
end

local function arith_mod(a, b)
	return a - arith_div(a, b) * b
end

local arith_ops3 = { "<<=", ">>=" }
local arith_ops2 = { "<<", ">>", "<=", ">=", "==", "!=", "&&", "||",
	"+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=" }
local arith_ops1 = "+-*/%~!<>&|^?:()="
local arith_assign = {
	["="] = true, ["+="] = true, ["-="] = true, ["*="] = true, ["/="] = true,
	["%="] = true, ["&="] = true, ["|="] = true, ["^="] = true,
	["<<="] = true, [">>="] = true,
}
local arith_levels = {
	{ "||" }, { "&&" }, { "|" }, { "^" }, { "&" },
	{ "==", "!=" }, { "<", "<=", ">", ">=" }, { "<<", ">>" },
	{ "+", "-" }, { "*", "/", "%" },
}

local function arith_lex(src)
	local toks, i = {}, 1
	while i <= #src do
		local c = src:sub(i, i)
		if c:match("%s") then
			i = i + 1
		elseif c:match("%d") then
			local num = src:match("^0[xX]%x+", i) or src:match("^%w+", i)
			toks[#toks + 1] = { t = "num", v = num }
			i = i + #num
		elseif c:match("[%a_]") then
			local name = src:match("^[%a_][%w_]*", i)
			toks[#toks + 1] = { t = "name", v = name }
			i = i + #name
		else
			local op
			for _, cand in ipairs(arith_ops3) do
				if src:sub(i, i + 2) == cand then op = cand break end
			end
			if not op then
				for _, cand in ipairs(arith_ops2) do
					if src:sub(i, i + 1) == cand then op = cand break end
				end
			end
			if not op then
				if not arith_ops1:find(c, 1, true) then
					arith_fail("unexpected character '" .. c .. "'")
				end
				op = c
			end
			toks[#toks + 1] = { t = "op", v = op }
			i = i + #op
		end
	end
	return toks
end

local arith_value

-- Evaluate a token list. depth guards against a variable that refers to itself.
local function arith_parse(toks, depth)
	local pos = 1
	-- above zero while inside a branch that short-circuiting skipped: no
	-- assignment happens and a division by zero yields 0 instead of failing
	local dead = 0

	local function peek()
		local t = toks[pos]
		return t and t.v
	end

	local function accept(v)
		if peek() == v then
			pos = pos + 1
			return true
		end
		return false
	end

	local function apply(op, a, b)
		if op == "*" then return a * b
		elseif op == "/" then
			if b == 0 then
				if dead > 0 then return 0 end
				arith_fail("division by zero")
			end
			return arith_div(a, b)
		elseif op == "%" then
			if b == 0 then
				if dead > 0 then return 0 end
				arith_fail("division by zero")
			end
			return arith_mod(a, b)
		elseif op == "+" then return a + b
		elseif op == "-" then return a - b
		elseif op == "<<" then return a << b
		elseif op == ">>" then return a >> b
		elseif op == "<" then return a < b and 1 or 0
		elseif op == "<=" then return a <= b and 1 or 0
		elseif op == ">" then return a > b and 1 or 0
		elseif op == ">=" then return a >= b and 1 or 0
		elseif op == "==" then return a == b and 1 or 0
		elseif op == "!=" then return a ~= b and 1 or 0
		elseif op == "&" then return a & b
		elseif op == "^" then return a ~ b
		elseif op == "|" then return a | b
		end
		arith_fail("unknown operator '" .. op .. "'")
	end

	local function value_of(name)
		local raw = env.get(name)
		if raw == nil or raw == "" then return 0 end
		if depth > 32 then arith_fail("expansion too deep: " .. name) end
		return arith_value(raw, depth + 1)
	end

	local assign_expr, binary

	local function primary()
		local t = toks[pos]
		if not t then arith_fail("unexpected end of expression") end
		if t.t == "num" then
			pos = pos + 1
			return arith_number(t.v)
		elseif t.t == "name" then
			pos = pos + 1
			return value_of(t.v)
		elseif t.v == "(" then
			pos = pos + 1
			local v = assign_expr()
			if not accept(")") then arith_fail("missing )") end
			return v
		end
		arith_fail("unexpected '" .. t.v .. "'")
	end

	local function unary()
		local v = peek()
		if v == "-" then pos = pos + 1 return -unary() end
		if v == "+" then pos = pos + 1 return unary() end
		if v == "!" then pos = pos + 1 return unary() == 0 and 1 or 0 end
		if v == "~" then pos = pos + 1 return ~unary() end
		return primary()
	end

	function binary(level)
		if level > #arith_levels then return unary() end
		local lhs = binary(level + 1)
		while true do
			local v = peek()
			local op
			for _, cand in ipairs(arith_levels[level]) do
				if v == cand then op = cand break end
			end
			if not op then return lhs end
			pos = pos + 1
			if op == "&&" or op == "||" then
				local taken = (op == "&&") == (lhs ~= 0)
				if not taken then dead = dead + 1 end
				local rhs = binary(level + 1)
				if not taken then dead = dead - 1 end
				if op == "&&" then
					lhs = (lhs ~= 0 and rhs ~= 0) and 1 or 0
				else
					lhs = (lhs ~= 0 or rhs ~= 0) and 1 or 0
				end
			else
				lhs = apply(op, lhs, binary(level + 1))
			end
		end
	end

	local function conditional()
		local cond = binary(1)
		if not accept("?") then return cond end
		local live = cond ~= 0
		if not live then dead = dead + 1 end
		local a = assign_expr()
		if not live then dead = dead - 1 end
		if not accept(":") then arith_fail("missing : in ?:") end
		if live then dead = dead + 1 end
		local b = conditional()
		if live then dead = dead - 1 end
		if live then return a end
		return b
	end

	function assign_expr()
		local name_tok, op_tok = toks[pos], toks[pos + 1]
		if name_tok and name_tok.t == "name" and op_tok and op_tok.t == "op"
			and arith_assign[op_tok.v] then
			pos = pos + 2
			local rhs = assign_expr()
			local val = rhs
			if op_tok.v ~= "=" then
				val = apply(op_tok.v:sub(1, -2), value_of(name_tok.v), rhs)
			end
			if dead == 0 then env.set(name_tok.v, tostring(val)) end
			return val
		end
		return conditional()
	end

	local result = assign_expr()
	if toks[pos] then arith_fail("unexpected '" .. toks[pos].v .. "'") end
	return result
end

function arith_value(text, depth)
	return arith_parse(arith_lex(text), depth)
end

arith_eval = function(expr)
	local ok, result = pcall(arith_value, word(expr), 0)
	if ok then return tostring(result) end
	local msg = type(result) == "table" and result.arith or tostring(result)
	fatal("arithmetic: " .. msg, 2)
	return "0"
end

-- Same grammar as word_pat, but each piece is kept separate and tagged so
-- field splitting can tell an unquoted expansion from literal text, and
-- so "$@" can become one field per positional parameter.
local function tag_literal(v)
	return { text = v, split = false }
end

local function tag_split(v)
	return { text = v, split = true }
end

local function tag_params()
	return { params = true }
end

local params_ref = (P("$@") + P("${@}")) / tag_params

-- A double-quoted section is kept as a list of parts, because "$@" inside
-- it ends one field and starts the next.
local dq_part = params_ref + cmdsub_pat + dollar_exp + dq_escape
	+ C(1 - P('"') - P("\\"))
local dq_section = P('"') * Ct(dq_part ^ 0) * P('"') / function(parts)
	return { quoted = true, parts = parts }
end

local piece_pat = Ct((
	sq_lit / tag_literal
	+ dq_section
	+ params_ref
	+ (cmdsub_pat + dollar_exp) / tag_split
	+ C(1 - lpeg.S("'\"")) / tag_literal
) ^ 0)

local function is_ifs_white(c)
	return c == " " or c == "\t" or c == "\n"
end

-- Expand a word and split the results of unquoted expansions on IFS.
-- Literal and quoted text never splits. Returns a list of fields.
local function expand_fields(s)
	local pieces = lpeg.match(piece_pat, s)
	if not pieces then return { word(s) } end
	local ifs = env.get("IFS")
	if ifs == nil then ifs = " \t\n" end
	local fields = {}
	local cur = nil

	local function flush()
		fields[#fields + 1] = cur or ""
		cur = nil
	end

	-- add text that came from an unquoted expansion, breaking it at IFS
	local function add_split(text)
		local i = 1
		while i <= #text do
			local c = text:sub(i, i)
			if not ifs:find(c, 1, true) then
				cur = (cur or "") .. c
				i = i + 1
			else
				-- one delimiter: a run of IFS whitespace around at most
				-- one non-whitespace IFS character
				local sawnonwhite = false
				while i <= #text do
					local d = text:sub(i, i)
					if not ifs:find(d, 1, true) then break end
					if is_ifs_white(d) then
						i = i + 1
					elseif not sawnonwhite then
						sawnonwhite = true
						i = i + 1
					else
						break
					end
				end
				if cur ~= nil or sawnonwhite then flush() end
			end
		end
	end

	-- "$@" is one field per positional parameter: the first joins whatever
	-- precedes it, the last stays open for whatever follows.
	local function add_params(split)
		local argv = env.get_argv()
		for i = 2, #argv do
			if i > 2 then flush() end
			if split and ifs ~= "" then
				add_split(argv[i])
			else
				cur = (cur or "") .. argv[i]
			end
		end
	end

	for _, piece in ipairs(pieces) do
		if piece.params then
			add_params(true)
		elseif piece.quoted then
			if #piece.parts == 0 then cur = cur or "" end
			for _, part in ipairs(piece.parts) do
				if type(part) == "table" and part.params then
					add_params(false)
				else
					cur = (cur or "") .. part
				end
			end
		elseif not piece.split or ifs == "" then
			cur = (cur or "") .. piece.text
		else
			add_split(piece.text)
		end
	end
	if cur ~= nil then fields[#fields + 1] = cur end
	return fields
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
	local fields = expand_fields(s)
	if not has_unquoted_glob(s) then
		return fields
	end
	local out = {}
	for _, field in ipairs(fields) do
		local matches = posix_glob.glob(field, 0)
		if matches then
			table.sort(matches)
			for _, m in ipairs(matches) do out[#out + 1] = m end
		else
			-- No matches: the pattern stands for itself (POSIX)
			out[#out + 1] = field
		end
	end
	return out
end

return {
	word = word,
	heredoc = heredoc,
	glob_word = glob_word,
	expand_fields = expand_fields,
	is_assignment = is_assignment,
	parse_assignment = parse_assignment,
	set_sh_path = set_sh_path,
	set_run_fn = set_run_fn,
	get_run_fn = function() return run_fn end,
}
