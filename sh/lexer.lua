-- SPDX-License-Identifier: ISC
-- sh/lexer.lua: tokenize a shell command line into words and operators
local lpeg = require("lpeg")
local P, S, C, Ct = lpeg.P, lpeg.S, lpeg.C, lpeg.Ct

local blank = S(" \t")
local newline = P("\n")
local comment = P("#") * (1 - newline) ^ 0

-- single-quoted: literal content, no escapes
local sq = P("'") * C((1 - P("'")) ^ 0) * P("'")

-- double-quoted: literal for now (no expansion in this phase)
local dq = P('"') * C((1 - P('"')) ^ 0) * P('"')

-- backslash escape: consume backslash, capture next char literally
local escape = P("\\") * C(P(1))

-- unquoted word chars: anything not blank, newline, quote, backslash, #, |, &, ;, $
local wordchar = 1 - S(" \t\n\"'\\#|&;$<>`")

-- $(...) command substitution: capture the whole $(...) including delimiters as literal text
local Cmt = lpeg.Cmt
local cmdsub = Cmt(P("$"), function(s, p)
	if s:sub(p, p) ~= "(" then
		return nil
	end
	local depth = 0
	local i = p
	while i <= #s do
		local c = s:sub(i, i)
		if c == "(" then
			depth = depth + 1
		elseif c == ")" then
			depth = depth - 1
			if depth == 0 then
				return i + 1, s:sub(p - 1, i) -- capture "$(...)"
			end
		end
		i = i + 1
	end
	return nil
end)

-- backtick command substitution: capture as $(...) equivalent
local backtick = P("`") * C((1 - P("`")) ^ 0) * P("`") / function(inner)
	return "$(" .. inner .. ")"
end

-- bare $VAR or $? etc - capture as literal text for later expansion
local dollar_lit =
	C(P("${") * (1 - P("}")) ^ 1 * P("}")) +
	C(P("$") * (lpeg.R("az", "AZ") + P("_") + lpeg.S("?$!-@*#0")) * (lpeg.R("az", "AZ", "09") + P("_")) ^ 0)

-- redirection operators: capture as literal word tokens (>> before >)
local redir = C(P(">>") + P(">&") + P("<&") + P(">") + P("<"))

-- a word is one or more segments concatenated
local segment = escape + sq + dq + cmdsub + backtick + dollar_lit + C(wordchar ^ 1)
local word = segment * segment ^ 0

local function fold_word(...)
	return table.concat({ ... })
end

-- operators: order matters (|| before |, && before &)
local and_op = P("&&") / function()
	return { op = "&&" }
end
local or_op = P("||") / function()
	return { op = "||" }
end
local pipe_op = P("|") / function()
	return { op = "|" }
end
local semi_op = (P(";") + P("\n")) / function()
	return { op = ";" }
end
local async_op = P("&") / function()
	return { op = "&" }
end

local operator = and_op + or_op + pipe_op + semi_op + async_op
local token = operator + redir + (word / fold_word)
local tokens = Ct((blank ^ 0 * token) ^ 0) * (blank ^ 0 * comment) ^ -1

-- Parse a line into a "list": array of and_or entries separated by ;
-- Each and_or is: { {pipeline, op, pipeline, op, ...} }
-- A pipeline is: { {args}, {args}, ... }
--
-- Returns: list = array of and_or_lists
-- and_or_list = array of { pipeline = {...}, op = "&&"|"||"|nil }
local function tokenize(line)
	-- POSIX: strip \<newline> (line continuation) before tokenization
	line = line:gsub("\\\n", "")
	local flat = lpeg.match(tokens, line)
	if not flat then
		return nil, "tokenize error"
	end

	-- First pass: split into pipelines and list/and_or operators
	local list = {} -- array of and_or chains
	local chain = {} -- current and_or chain: {pipeline, op, pipeline, op, ...}
	local pipeline = {} -- current pipeline segments
	local current = {} -- current command args

	for _, tok in ipairs(flat) do
		if type(tok) == "table" then
			if tok.op == "|" then
				pipeline[#pipeline + 1] = current
				current = {}
			elseif tok.op == "&&" or tok.op == "||" then
				pipeline[#pipeline + 1] = current
				current = {}
				chain[#chain + 1] = { pipeline = pipeline, op = tok.op }
				pipeline = {}
			elseif tok.op == ";" then
				pipeline[#pipeline + 1] = current
				current = {}
				chain[#chain + 1] = { pipeline = pipeline }
				pipeline = {}
				list[#list + 1] = { chain = chain, async = false }
				chain = {}
			elseif tok.op == "&" then
				pipeline[#pipeline + 1] = current
				current = {}
				chain[#chain + 1] = { pipeline = pipeline }
				pipeline = {}
				list[#list + 1] = { chain = chain, async = true }
				chain = {}
			end
		else
			current[#current + 1] = tok
		end
	end

	-- flush remaining
	pipeline[#pipeline + 1] = current
	chain[#chain + 1] = { pipeline = pipeline }
	list[#list + 1] = { chain = chain, async = false }

	return list
end

-- tokenize_flat: return just the flat token array (words + operator tables)
local function tokenize_flat(line)
	line = line:gsub("\\\n", "")
	local flat = lpeg.match(tokens, line)
	if not flat then
		return nil, "tokenize error"
	end
	-- flatten: convert operator tables to their string, keep words as-is
	local result = {}
	for _, tok in ipairs(flat) do
		if type(tok) == "table" then
			result[#result + 1] = tok.op
		else
			result[#result + 1] = tok
		end
	end
	return result
end

return { tokenize = tokenize, tokenize_flat = tokenize_flat }
