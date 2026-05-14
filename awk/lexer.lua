-- SPDX-License-Identifier: ISC
-- awk/lexer.lua - tokenizer for POSIX awk
local lpeg = require("lpeg")
local P, R, S, C, Ct, Cc, Cp, Cg, Cf, V = lpeg.P, lpeg.R, lpeg.S, lpeg.C, lpeg.Ct, lpeg.Cc, lpeg.Cp, lpeg.Cg, lpeg.Cf, lpeg.V

local M = {}

local keywords = {
	["BEGIN"] = "Begin", ["END"] = "End",
	["break"] = "Break", ["continue"] = "Continue", ["delete"] = "Delete",
	["do"] = "Do", ["else"] = "Else", ["exit"] = "Exit",
	["for"] = "For", ["function"] = "Function", ["if"] = "If",
	["in"] = "In", ["next"] = "Next", ["print"] = "Print",
	["printf"] = "Printf", ["return"] = "Return", ["while"] = "While",
	["getline"] = "Getline",
}

local builtins = {}
for _, name in ipairs({
	"atan2", "cos", "sin", "exp", "log", "sqrt", "int", "rand", "srand",
	"gsub", "index", "length", "match", "split", "sprintf", "sub",
	"substr", "tolower", "toupper", "close", "system",
}) do
	builtins[name] = true
end

-- Token types that indicate the next / should be division rather than ERE.
-- After these tokens, a / cannot start a regex literal.
local div_after = {
	NAME = true, NUMBER = true, STRING = true,
	RPAREN = true, RBRACKET = true, INCR = true, DECR = true,
}

-- Tokenize an awk program source string into a list of {type, value} tokens.
-- Handles the ERE vs division ambiguity, FUNC_NAME detection, line continuation,
-- comments, and C-style string/ERE escape sequences.
function M.tokenize(src)
	-- Ensure trailing newline
	if src:sub(-1) ~= "\n" then src = src .. "\n" end

	local tokens = {}
	local pos = 1
	local len = #src

	local function peek() return src:sub(pos, pos) end
	local function advance() pos = pos + 1 end
	local function at_end() return pos > len end
	local function ch_at(i) return src:sub(i, i) end

	local function emit(typ, val)
		tokens[#tokens + 1] = { type = typ, value = val }
	end

	-- Return the type of the last non-NEWLINE token (for ERE/division disambiguation)
	local function last_type()
		for i = #tokens, 1, -1 do
			if tokens[i].type ~= "NEWLINE" then return tokens[i].type end
		end
		return nil
	end

	-- Skip whitespace, line continuations (backslash-newline), and comments
	local function skip_ws()
		while pos <= len do
			local c = ch_at(pos)
			if c == " " or c == "\t" then
				pos = pos + 1
			elseif c == "\\" and pos + 1 <= len and ch_at(pos + 1) == "\n" then
				pos = pos + 2
			elseif c == "#" then
				while pos <= len and ch_at(pos) ~= "\n" do pos = pos + 1 end
			else
				break
			end
		end
	end

	-- Read a double-quoted string literal, processing escape sequences.
	-- pos should be at the opening ". Returns the unescaped string value.
	local function read_string()
		pos = pos + 1 -- skip opening "
		local buf = {}
		while pos <= len do
			local c = ch_at(pos)
			if c == '"' then pos = pos + 1; return table.concat(buf) end
			if c == "\\" then
				pos = pos + 1
				local e = ch_at(pos)
				if e == "n" then buf[#buf + 1] = "\n"
				elseif e == "t" then buf[#buf + 1] = "\t"
				elseif e == "r" then buf[#buf + 1] = "\r"
				elseif e == "a" then buf[#buf + 1] = "\a"
				elseif e == "b" then buf[#buf + 1] = "\b"
				elseif e == "f" then buf[#buf + 1] = "\f"
				elseif e == "v" then buf[#buf + 1] = "\v"
				elseif e == "\\" then buf[#buf + 1] = "\\"
				elseif e == '"' then buf[#buf + 1] = '"'
				elseif e == "/" then buf[#buf + 1] = "/"
				elseif e >= "0" and e <= "7" then
					local oct = e
					for _ = 1, 2 do
						if pos + 1 <= len and ch_at(pos + 1) >= "0" and ch_at(pos + 1) <= "7" then
							pos = pos + 1; oct = oct .. ch_at(pos)
						end
					end
					buf[#buf + 1] = string.char(tonumber(oct, 8))
				else
					buf[#buf + 1] = "\\" .. e
				end
			else
				buf[#buf + 1] = c
			end
			pos = pos + 1
		end
		error("unterminated string")
	end

	-- Read an ERE (extended regular expression) literal between /.../.
	-- Backslash escapes are preserved verbatim for the regex engine.
	local function read_ere()
		pos = pos + 1 -- skip opening /
		local buf = {}
		while pos <= len do
			local c = ch_at(pos)
			if c == "/" then pos = pos + 1; return table.concat(buf) end
			if c == "\\" then
				buf[#buf + 1] = c
				pos = pos + 1
				if pos <= len then buf[#buf + 1] = ch_at(pos) end
			else
				buf[#buf + 1] = c
			end
			pos = pos + 1
		end
		error("unterminated ERE")
	end

	-- Read a numeric literal (integer, float, or scientific notation)
	local function read_number()
		local start = pos
		-- integer or float
		while pos <= len and ch_at(pos) >= "0" and ch_at(pos) <= "9" do pos = pos + 1 end
		if pos <= len and ch_at(pos) == "." then
			pos = pos + 1
			while pos <= len and ch_at(pos) >= "0" and ch_at(pos) <= "9" do pos = pos + 1 end
		end
		if pos <= len and (ch_at(pos) == "e" or ch_at(pos) == "E") then
			pos = pos + 1
			if pos <= len and (ch_at(pos) == "+" or ch_at(pos) == "-") then pos = pos + 1 end
			while pos <= len and ch_at(pos) >= "0" and ch_at(pos) <= "9" do pos = pos + 1 end
		end
		return src:sub(start, pos - 1)
	end

	-- Read an identifier (keyword, builtin name, NAME, or FUNC_NAME)
	local function read_word()
		local start = pos
		while pos <= len do
			local c = ch_at(pos)
			if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_" then
				pos = pos + 1
			else
				break
			end
		end
		return src:sub(start, pos - 1)
	end

	while true do
		skip_ws()
		if at_end() then break end
		local c = ch_at(pos)

		if c == "\n" then
			emit("NEWLINE", "\n")
			pos = pos + 1
		elseif c == '"' then
			emit("STRING", read_string())
		elseif c == "/" then
			-- ERE vs division ambiguity
			if div_after[last_type()] then
				-- check for /=
				if pos + 1 <= len and ch_at(pos + 1) == "=" then
					emit("DIV_ASSIGN", "/="); pos = pos + 2
				else
					emit("/", "/"); pos = pos + 1
				end
			else
				emit("ERE", read_ere())
			end
		elseif (c >= "0" and c <= "9") or (c == "." and pos + 1 <= len and ch_at(pos + 1) >= "0" and ch_at(pos + 1) <= "9") then
			emit("NUMBER", read_number())
		elseif (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_" then
			local word = read_word()
			if keywords[word] then
				emit(keywords[word], word)
			elseif builtins[word] then
				-- check if followed by ( without space
				if pos <= len and ch_at(pos) == "(" then
					emit("BUILTIN_FUNC_NAME", word)
				else
					emit("BUILTIN_FUNC_NAME", word)
				end
			else
				-- NAME or FUNC_NAME: FUNC_NAME if immediately followed by (
				if pos <= len and ch_at(pos) == "(" then
					emit("FUNC_NAME", word)
				else
					emit("NAME", word)
				end
			end
		elseif c == "+" then
			if pos + 1 <= len and ch_at(pos + 1) == "+" then emit("INCR", "++"); pos = pos + 2
			elseif pos + 1 <= len and ch_at(pos + 1) == "=" then emit("ADD_ASSIGN", "+="); pos = pos + 2
			else emit("+", "+"); pos = pos + 1 end
		elseif c == "-" then
			if pos + 1 <= len and ch_at(pos + 1) == "-" then emit("DECR", "--"); pos = pos + 2
			elseif pos + 1 <= len and ch_at(pos + 1) == "=" then emit("SUB_ASSIGN", "-="); pos = pos + 2
			else emit("-", "-"); pos = pos + 1 end
		elseif c == "*" then
			if pos + 1 <= len and ch_at(pos + 1) == "=" then emit("MUL_ASSIGN", "*="); pos = pos + 2
			else emit("*", "*"); pos = pos + 1 end
		elseif c == "%" then
			if pos + 1 <= len and ch_at(pos + 1) == "=" then emit("MOD_ASSIGN", "%="); pos = pos + 2
			else emit("%", "%"); pos = pos + 1 end
		elseif c == "^" then
			if pos + 1 <= len and ch_at(pos + 1) == "=" then emit("POW_ASSIGN", "^="); pos = pos + 2
			else emit("^", "^"); pos = pos + 1 end
		elseif c == "=" then
			if pos + 1 <= len and ch_at(pos + 1) == "=" then emit("EQ", "=="); pos = pos + 2
			else emit("=", "="); pos = pos + 1 end
		elseif c == "!" then
			if pos + 1 <= len and ch_at(pos + 1) == "=" then emit("NE", "!="); pos = pos + 2
			elseif pos + 1 <= len and ch_at(pos + 1) == "~" then emit("NO_MATCH", "!~"); pos = pos + 2
			else emit("!", "!"); pos = pos + 1 end
		elseif c == "<" then
			if pos + 1 <= len and ch_at(pos + 1) == "=" then emit("LE", "<="); pos = pos + 2
			else emit("<", "<"); pos = pos + 1 end
		elseif c == ">" then
			if pos + 1 <= len and ch_at(pos + 1) == "=" then emit("GE", ">="); pos = pos + 2
			elseif pos + 1 <= len and ch_at(pos + 1) == ">" then emit("APPEND", ">>"); pos = pos + 2
			else emit(">", ">"); pos = pos + 1 end
		elseif c == "|" then
			if pos + 1 <= len and ch_at(pos + 1) == "|" then emit("OR", "||"); pos = pos + 2
			else emit("|", "|"); pos = pos + 1 end
		elseif c == "&" then
			if pos + 1 <= len and ch_at(pos + 1) == "&" then emit("AND", "&&"); pos = pos + 2
			else emit("&", "&"); pos = pos + 1 end
		elseif c == "~" then emit("~", "~"); pos = pos + 1
		elseif c == "$" then emit("$", "$"); pos = pos + 1
		elseif c == "?" then emit("?", "?"); pos = pos + 1
		elseif c == ":" then emit(":", ":"); pos = pos + 1
		elseif c == "," then emit(",", ","); pos = pos + 1
		elseif c == ";" then emit(";", ";"); pos = pos + 1
		elseif c == "{" then emit("{", "{"); pos = pos + 1
		elseif c == "}" then emit("}", "}"); pos = pos + 1
		elseif c == "(" then emit("(", "("); pos = pos + 1
		elseif c == ")" then emit(")", ")"); pos = pos + 1
		elseif c == "[" then emit("[", "["); pos = pos + 1
		elseif c == "]" then emit("]", "]"); pos = pos + 1
		else
			error("unexpected character: " .. c .. " at position " .. pos)
		end
	end

	return tokens
end

return M
