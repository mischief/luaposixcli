-- SPDX-License-Identifier: ISC
-- sh/parse.lua: POSIX shell parser - token stream → AST
--
-- Grammar (simplified):
--   program     = linebreak complete_commands linebreak
--   complete_cmd = list separator_op?
--   list        = and_or (separator_op and_or)*
--   and_or      = pipeline (("&&"|"||") linebreak pipeline)*
--   pipeline    = "!"? command ("|" linebreak command)*
--   command     = simple_cmd | compound_cmd redirect_list? | function_def
--   compound_cmd = brace_group | subshell | for_clause | case_clause
--                | if_clause | while_clause | until_clause
--   simple_cmd  = (assignment|word|redirect)+
--   function_def = name "(" ")" linebreak function_body
--   function_body = compound_cmd redirect_list?

local M = {}

-- Parser state
local tokens, pos

local function peek()
	return tokens[pos]
end

local function at(s)
	return tokens[pos] == s
end

local function advance()
	pos = pos + 1
end

local function consume(expected)
	if tokens[pos] ~= expected then
		return nil, "expected '" .. expected .. "' got '" .. tostring(tokens[pos]) .. "'"
	end
	pos = pos + 1
	return true
end

local function skip_newlines()
	while tokens[pos] == ";" and pos <= #tokens do
		-- In our token stream, newlines are represented as ";"
		-- We only skip them in contexts where newlines are line breaks (after && || |)
		advance()
	end
end

-- Check if token is a redirection operator
local function is_redir(t)
	return t == ">" or t == ">>" or t == "<" or t == ">&" or t == "<&" or t == "<<" or t == "<<-"
end

-- Check if token is a separator
local function is_separator(t)
	return t == ";" or t == "&"
end

-- Check if token is a reserved word
local reserved = {
	["if"]=true, ["then"]=true, ["else"]=true, ["elif"]=true, ["fi"]=true,
	["while"]=true, ["until"]=true, ["do"]=true, ["done"]=true,
	["for"]=true, ["in"]=true, ["case"]=true, ["esac"]=true,
	["{"]=true, ["}"]=true, ["!"]=true,
}

-- Forward declarations
local parse_list, parse_and_or, parse_pipeline, parse_command
local parse_simple_command, parse_compound_command
local parse_if, parse_while, parse_until, parse_for, parse_case
local parse_brace_group, parse_subshell, parse_redirect_list

-- Parse a complete command list (top-level or body of compound command)
-- Stops at: EOF, "}", ")", "fi", "done", "esac", "elif", "else", "then", "do"
local function is_terminator(t)
	return t == nil or t == "}" or t == ")" or t == "fi" or t == "done"
		or t == "esac" or t == "elif" or t == "else" or t == "then" or t == "do"
end

-- parse_compound_list: list of and_or separated by ; or &, terminated by a keyword
local function parse_compound_list()
	local items = {}
	while not is_terminator(peek()) do
		-- skip leading separators
		while peek() == ";" do advance() end
		if is_terminator(peek()) then break end
		local node = parse_and_or()
		if not node then break end
		-- check for async
		if peek() == "&" then
			advance()
			node = { type = "async", body = node }
		elseif peek() == ";" then
			advance()
		end
		items[#items + 1] = node
	end
	if #items == 0 then return nil end
	if #items == 1 then return items[1] end
	return { type = "list", items = items }
end

-- parse_list: for top-level (one complete command)
function parse_list()
	return parse_compound_list()
end

-- parse_and_or: pipeline (("&&"|"||") linebreak pipeline)*
function parse_and_or()
	local left = parse_pipeline()
	if not left then return nil end
	while peek() == "&&" or peek() == "||" do
		local op = peek()
		advance()
		-- skip newlines after && ||
		while peek() == ";" do advance() end
		local right = parse_pipeline()
		if not right then break end
		left = { type = "and_or", op = op, left = left, right = right }
	end
	return left
end

-- parse_pipeline: "!"? command ("|" linebreak command)*
function parse_pipeline()
	local bang = false
	if peek() == "!" then
		bang = true
		advance()
	end
	local cmd = parse_command()
	if not cmd then return nil end
	local cmds = { cmd }
	while peek() == "|" do
		advance()
		while peek() == ";" do advance() end -- skip newlines after |
		cmd = parse_command()
		if not cmd then break end
		cmds[#cmds + 1] = cmd
	end
	if #cmds == 1 and not bang then return cmds[1] end
	return { type = "pipeline", cmds = cmds, bang = bang }
end

-- parse_command: compound_command redirect_list? | function_def | simple_command
function parse_command()
	local t = peek()
	if not t then return nil end

	-- compound commands
	if t == "if" then return parse_if()
	elseif t == "while" then return parse_while()
	elseif t == "until" then return parse_until()
	elseif t == "for" then return parse_for()
	elseif t == "case" then return parse_case()
	elseif t == "{" then return parse_brace_group()
	elseif t == "(" then return parse_subshell()
	end

	-- function definition: NAME ( ) compound_command
	if t and not reserved[t] and tokens[pos + 1] == "(" and tokens[pos + 2] == ")" then
		local name = t
		advance() -- name
		advance() -- (
		advance() -- )
		while peek() == ";" do advance() end
		local body = parse_compound_command()
		if body then
			local redirs = parse_redirect_list()
			return { type = "function", name = name, body = body, redirs = redirs }
		end
	end

	return parse_simple_command()
end

-- parse_compound_command (for function bodies)
function parse_compound_command()
	local t = peek()
	if t == "{" then return parse_brace_group()
	elseif t == "(" then return parse_subshell()
	elseif t == "if" then return parse_if()
	elseif t == "while" then return parse_while()
	elseif t == "until" then return parse_until()
	elseif t == "for" then return parse_for()
	elseif t == "case" then return parse_case()
	end
	return nil
end

-- parse_simple_command: (assignment|word|redirect)+
function parse_simple_command()
	local assigns = {}
	local words = {}
	local redirs = {}
	local heredocs = {} -- {delimiter, strip_tabs, quoted}

	while true do
		local t = peek()
		if not t or is_separator(t) or t == "|" or t == "&&" or t == "||"
			or t == ")" or t == "}" or t == ";;" or is_terminator(t) then
			break
		end
		if is_redir(t) then
			-- Check if previous word is a fd number
			local fd
			if #words > 0 and words[#words]:match("^%d+$") then
				fd = tonumber(table.remove(words))
			end
			local op = t
			advance()
			local target = peek()
			if target then advance() end
			if op == "<<" or op == "<<-" then
				-- Here-document: target is the delimiter
				local strip = (op == "<<-")
				local quoted = false
				if target then
					-- If delimiter is quoted, no expansion in body
					if target:sub(1, 1) == "'" or target:sub(1, 1) == '"' then
						quoted = true
						target = target:sub(2, -2) -- strip quotes
					end
				end
				heredocs[#heredocs + 1] = { delim = target, strip = strip, quoted = quoted, fd = fd or 0 }
				redirs[#redirs + 1] = { op = "<<", fd = fd or 0, heredoc_idx = #heredocs }
			else
				redirs[#redirs + 1] = { op = op, fd = fd, target = target }
			end
		elseif #words == 0 and not reserved[t] and t:find("=") and t:match("^[%a_][%w_]*=") then
			-- Assignment (only before any words)
			assigns[#assigns + 1] = t
			advance()
		else
			words[#words + 1] = t
			advance()
		end
	end

	if #assigns == 0 and #words == 0 and #redirs == 0 then return nil end
	return { type = "simple", assigns = assigns, words = words, redirs = redirs, heredocs = heredocs }
end

-- parse_redirect_list: collect trailing redirections for compound commands
function parse_redirect_list()
	local redirs = {}
	while true do
		local t = peek()
		if not t or not is_redir(t) then break end
		local fd
		-- fd number would have been consumed as part of the compound command... skip for now
		local op = t
		advance()
		local target = peek()
		if target then advance() end
		redirs[#redirs + 1] = { op = op, target = target }
	end
	if #redirs == 0 then return nil end
	return redirs
end

-- parse_if: "if" compound_list "then" compound_list ("elif" compound_list "then" compound_list)* ("else" compound_list)? "fi"
function parse_if()
	advance() -- consume "if"
	local cond = parse_compound_list()
	consume("then")
	local then_body = parse_compound_list()
	local elifs = {}
	local else_body = nil
	while peek() == "elif" do
		advance()
		local econd = parse_compound_list()
		consume("then")
		local ebody = parse_compound_list()
		elifs[#elifs + 1] = { cond = econd, body = ebody }
	end
	if peek() == "else" then
		advance()
		else_body = parse_compound_list()
	end
	consume("fi")
	local redirs = parse_redirect_list()
	return { type = "if", cond = cond, then_body = then_body, elifs = elifs, else_body = else_body, redirs = redirs }
end

-- parse_while: "while" compound_list "do" compound_list "done"
function parse_while()
	advance() -- consume "while"
	local cond = parse_compound_list()
	consume("do")
	local body = parse_compound_list()
	consume("done")
	local redirs = parse_redirect_list()
	return { type = "while", cond = cond, body = body, redirs = redirs }
end

-- parse_until: "until" compound_list "do" compound_list "done"
function parse_until()
	advance() -- consume "until"
	local cond = parse_compound_list()
	consume("do")
	local body = parse_compound_list()
	consume("done")
	local redirs = parse_redirect_list()
	return { type = "until", cond = cond, body = body, redirs = redirs }
end

-- parse_for: "for" name ("in" word*)? separator "do" compound_list "done"
function parse_for()
	advance() -- consume "for"
	local name = peek(); advance()
	local wordlist = nil
	-- skip optional ;
	while peek() == ";" do advance() end
	if peek() == "in" then
		advance()
		wordlist = {}
		while peek() and peek() ~= ";" and peek() ~= "do" do
			wordlist[#wordlist + 1] = peek()
			advance()
		end
		while peek() == ";" do advance() end
	end
	consume("do")
	local body = parse_compound_list()
	consume("done")
	local redirs = parse_redirect_list()
	return { type = "for", name = name, wordlist = wordlist, body = body, redirs = redirs }
end

-- parse_case: "case" word "in" (pattern ("|" pattern)* ")" compound_list ";;"?)* "esac"
function parse_case()
	advance() -- consume "case"
	local word = peek(); advance()
	-- skip ; and "in"
	while peek() == ";" do advance() end
	consume("in")
	while peek() == ";" do advance() end
	local clauses = {}
	while peek() and peek() ~= "esac" do
		-- optional leading (
		if peek() == "(" then advance() end
		-- patterns separated by |
		local patterns = {}
		while peek() and peek() ~= ")" do
			if peek() ~= "|" then
				patterns[#patterns + 1] = peek()
			end
			advance()
		end
		consume(")")
		-- body until ;; or esac
		local body_items = {}
		while peek() and peek() ~= ";;" and peek() ~= "esac" do
			while peek() == ";" do advance() end
			if peek() == ";;" or peek() == "esac" then break end
			local node = parse_and_or()
			if node then body_items[#body_items + 1] = node end
			if peek() == ";" then advance() end
		end
		if peek() == ";;" then advance() end
		while peek() == ";" do advance() end
		local body = #body_items == 1 and body_items[1] or (#body_items > 0 and { type = "list", items = body_items } or nil)
		clauses[#clauses + 1] = { patterns = patterns, body = body }
	end
	consume("esac")
	local redirs = parse_redirect_list()
	return { type = "case", word = word, clauses = clauses, redirs = redirs }
end

-- parse_brace_group: "{" compound_list "}"
function parse_brace_group()
	advance() -- consume "{"
	local body = parse_compound_list()
	consume("}")
	local redirs = parse_redirect_list()
	return { type = "brace", body = body, redirs = redirs }
end

-- parse_subshell: "(" compound_list ")"
function parse_subshell()
	advance() -- consume "("
	local body = parse_compound_list()
	consume(")")
	local redirs = parse_redirect_list()
	return { type = "subshell", body = body, redirs = redirs }
end

--- Parse a token list into an AST.
--- Returns AST node, or nil + "incomplete" if more input needed.
function M.parse(token_list)
	tokens = token_list
	pos = 1
	-- Skip leading separators
	while peek() == ";" do advance() end
	if pos > #tokens then return nil end
	local ast = parse_compound_list()
	-- Check if we consumed everything
	if pos <= #tokens and not is_terminator(peek()) then
		-- Might be incomplete
		return nil, "incomplete"
	end
	return ast
end

--- Check if a token list represents a complete command.
--- Returns true if complete, false if more input is needed.
function M.is_complete(token_list)
	if not token_list then return true end
	-- Simple heuristic: count openers vs closers
	local depth = 0
	local in_case = 0
	for _, t in ipairs(token_list) do
		if t == "if" or t == "while" or t == "until" or t == "for" then
			depth = depth + 1
		elseif t == "case" then
			depth = depth + 1
			in_case = in_case + 1
		elseif t == "{" then
			depth = depth + 1
		elseif t == "(" and in_case == 0 then
			depth = depth + 1
		elseif t == "fi" or t == "done" then
			depth = depth - 1
		elseif t == "esac" then
			depth = depth - 1
			in_case = in_case - 1
		elseif t == "}" then
			depth = depth - 1
		elseif t == ")" and in_case == 0 then
			depth = depth - 1
		end
	end
	return depth <= 0
end

return M
