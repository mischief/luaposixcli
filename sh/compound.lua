-- SPDX-License-Identifier: ISC
-- sh/compound.lua: compound command parsing and execution
-- Works on the raw token list from the lexer (before list splitting)

local M = {}

-- run_fn is set by sh.lua to execute a string as a command
local run_fn = nil
function M.set_run_fn(fn)
	run_fn = fn
end

-- Check if a token list starts with a compound command keyword
function M.is_compound(tokens)
	if #tokens == 0 then
		return false
	end
	local first = tokens[1]
	return first == "if" or first == "while" or first == "until" or first == "for"
		or first == "(" or first == "{" or first == "case"
end

-- Find matching terminator, respecting nesting of ALL compound commands
local function find_matching(tokens, start, close_kw)
	local depth_fi = 0 -- if/fi
	local depth_done = 0 -- while/until/for / done
	-- the opener at start-1 already counts as depth 1
	if close_kw == "fi" then
		depth_fi = 1
	elseif close_kw == "done" then
		depth_done = 1
	end

	for i = start, #tokens do
		local t = tokens[i]
		if t == "if" then
			depth_fi = depth_fi + 1
		elseif t == "fi" then
			depth_fi = depth_fi - 1
			if close_kw == "fi" and depth_fi == 0 then
				return i
			end
		elseif t == "while" or t == "until" or t == "for" then
			depth_done = depth_done + 1
		elseif t == "done" then
			depth_done = depth_done - 1
			if close_kw == "done" and depth_done == 0 then
				return i
			end
		end
	end
	return nil
end

-- Split tokens on a keyword at depth 0, returns list of segments
local function split_on(tokens, start, stop, keywords)
	local kw_set = {}
	for _, k in ipairs(keywords) do
		kw_set[k] = true
	end
	local segments = {}
	local current = {}
	local depth_if, depth_while, depth_for = 0, 0, 0
	for i = start, stop do
		local t = tokens[i]
		-- track nesting
		if t == "if" then
			depth_if = depth_if + 1
		elseif t == "fi" then
			depth_if = depth_if - 1
		elseif t == "while" or t == "until" then
			depth_while = depth_while + 1
		elseif t == "done" then
			if depth_for > 0 then
				depth_for = depth_for - 1
			else
				depth_while = depth_while - 1
			end
		elseif t == "for" then
			depth_for = depth_for + 1
		end
		local at_top = (depth_if == 0 and depth_while == 0 and depth_for == 0)
		if at_top and kw_set[t] then
			segments[#segments + 1] = { tokens = current, keyword = t }
			current = {}
		else
			current[#current + 1] = t
		end
	end
	if #current > 0 then
		segments[#segments + 1] = { tokens = current }
	end
	return segments
end

-- Join tokens back into a command string for execution
local function tokens_to_string(tokens)
	local parts = {}
	for _, t in ipairs(tokens) do
		if type(t) == "table" then
			parts[#parts + 1] = t.op or ""
		else
			-- quote tokens that contain spaces
			if t:find(" ") then
				parts[#parts + 1] = "'" .. t:gsub("'", "'\\''") .. "'"
			else
				parts[#parts + 1] = t
			end
		end
	end
	return table.concat(parts, " ")
end

local function run_cmd(str)
	if run_fn and str ~= "" then
		run_fn(str)
	end
end

local function get_status()
	local env = require("sh.env")
	return tonumber(env.get("?")) or 0
end

-- Execute an if/elif/else/fi compound command
-- tokens: everything between (not including) 'if' and 'fi'
local function exec_if(tokens)
	-- Find positions of then/elif/else at top level
	local parts = {} -- {type="cond"|"body"|"else", tokens={...}}
	local depth = 0
	local current = {}
	local state = "cond" -- expecting condition first

	for _, t in ipairs(tokens) do
		if t == "if" then
			depth = depth + 1
			current[#current + 1] = t
		elseif t == "fi" then
			depth = depth - 1
			current[#current + 1] = t
		elseif depth == 0 and t == "then" then
			parts[#parts + 1] = { type = "cond", tokens = current }
			current = {}
		elseif depth == 0 and t == "elif" then
			parts[#parts + 1] = { type = "body", tokens = current }
			current = {}
		elseif depth == 0 and t == "else" then
			parts[#parts + 1] = { type = "body", tokens = current }
			current = {}
			state = "else"
		elseif t == ";" and depth == 0 and #current == 0 then
			-- skip leading ;
		else
			current[#current + 1] = t
		end
	end
	if #current > 0 then
		parts[#parts + 1] = { type = (state == "else") and "else" or "body", tokens = current }
	end

	-- Execute: pairs of (cond, body), optionally ending with else
	local i = 1
	while i <= #parts do
		local p = parts[i]
		if p.type == "cond" then
			run_cmd(tokens_to_string(p.tokens))
			i = i + 1
			if get_status() == 0 then
				-- execute body
				if i <= #parts then
					run_cmd(tokens_to_string(parts[i].tokens))
				end
				return
			else
				-- skip body
				i = i + 1
			end
		elseif p.type == "else" then
			run_cmd(tokens_to_string(p.tokens))
			return
		else
			i = i + 1
		end
	end
end

-- Execute while/until
local function exec_while(tokens, until_mode)
	-- find 'do' at top level
	local do_pos
	local depth = 0
	for i, t in ipairs(tokens) do
		if t == "while" or t == "until" or t == "for" then
			depth = depth + 1
		elseif t == "done" then
			depth = depth - 1
		elseif t == "do" and depth == 0 then
			do_pos = i
			break
		end
	end
	if not do_pos then
		return
	end
	local cond_tokens = {}
	for i = 1, do_pos - 1 do
		if not (tokens[i] == ";" and i == do_pos - 1) then
			cond_tokens[#cond_tokens + 1] = tokens[i]
		end
	end
	local body_tokens = {}
	for i = do_pos + 1, #tokens do
		body_tokens[#body_tokens + 1] = tokens[i]
	end
	local cond_str = tokens_to_string(cond_tokens)
	local body_str = tokens_to_string(body_tokens)
	local env = require("sh.env")
	while true do
		run_cmd(cond_str)
		local s = get_status()
		if until_mode then
			if s == 0 then
				break
			end
		else
			if s ~= 0 then
				break
			end
		end
		run_cmd(body_str)
		if env.get("_break") then
			local n = tonumber(env.get("_break"))
			env.unset("_break")
			if n and n > 1 then
				env.set("_break", tostring(n - 1))
			end
			break
		end
		if env.get("_continue") then
			local n = tonumber(env.get("_continue"))
			env.unset("_continue")
			if n and n > 1 then
				env.set("_continue", tostring(n - 1))
				break
			end
		end
	end
end

-- Execute for/in/do/done
local function exec_for(tokens)
	if #tokens == 0 then
		return
	end
	local varname = tokens[1]
	local expand = require("sh.expand")
	local env = require("sh.env")
	-- find 'in' and 'do' positions
	local in_pos, do_pos
	for i = 2, #tokens do
		if tokens[i] == "in" and not in_pos then
			in_pos = i
		elseif tokens[i] == "do" and not do_pos then
			do_pos = i
		end
	end
	-- collect word list (between 'in' and 'do')
	local wordlist = {}
	local wstart = in_pos and (in_pos + 1) or 2
	local wend = do_pos and (do_pos - 1) or #tokens
	for i = wstart, wend do
		if tokens[i] ~= ";" and tokens[i] ~= "" then
			wordlist[#wordlist + 1] = expand.word(tokens[i])
		end
	end
	-- collect body (after 'do')
	local body_tokens = {}
	if do_pos then
		for i = do_pos + 1, #tokens do
			body_tokens[#body_tokens + 1] = tokens[i]
		end
	end
	local body_str = tokens_to_string(body_tokens)
	for _, val in ipairs(wordlist) do
		env.set(varname, val)
		run_cmd(body_str)
		if env.get("_break") then
			local n = tonumber(env.get("_break"))
			env.unset("_break")
			if n and n > 1 then
				env.set("_break", tostring(n - 1))
			end
			break
		end
		if env.get("_continue") then
			local n = tonumber(env.get("_continue"))
			env.unset("_continue")
			if n and n > 1 then
				env.set("_continue", tostring(n - 1))
				break
			end
		end
	end
end

-- Shell pattern matching for case statements (* ? [...])
function M.case_match(str, pattern)
	-- Convert shell pattern to Lua pattern
	if pattern == "*" then return true end
	local lua_pat = "^"
	local i = 1
	while i <= #pattern do
		local c = pattern:sub(i, i)
		if c == "*" then
			lua_pat = lua_pat .. ".*"
		elseif c == "?" then
			lua_pat = lua_pat .. "."
		elseif c == "[" then
			local j = i + 1
			local neg = ""
			if j <= #pattern and pattern:sub(j, j) == "!" then
				neg = "^"; j = j + 1
			end
			local bracket = ""
			while j <= #pattern and pattern:sub(j, j) ~= "]" do
				bracket = bracket .. pattern:sub(j, j)
				j = j + 1
			end
			lua_pat = lua_pat .. "[" .. neg .. bracket .. "]"
			i = j
		elseif c:find("[%.%+%-%^%$%(%)%%]") then
			lua_pat = lua_pat .. "%" .. c
		else
			lua_pat = lua_pat .. c
		end
		i = i + 1
	end
	lua_pat = lua_pat .. "$"
	return str:find(lua_pat) ~= nil
end

-- Execute a compound command from a flat token list
-- Returns true if it handled a compound command, false otherwise
function M.try_execute(tokens)
	if #tokens == 0 then
		return false
	end
	local first = tokens[1]

	if first == "if" then
		local fi_idx = find_matching(tokens, 2, "fi")
		if not fi_idx then
			return false
		end
		local inner = {}
		for i = 2, fi_idx - 1 do
			inner[#inner + 1] = tokens[i]
		end
		exec_if(inner)
		return true
	elseif first == "while" then
		local done_idx = find_matching(tokens, 2, "done")
		if not done_idx then
			return false
		end
		local inner = {}
		for i = 2, done_idx - 1 do
			inner[#inner + 1] = tokens[i]
		end
		exec_while(inner, false)
		return true
	elseif first == "until" then
		local done_idx = find_matching(tokens, 2, "done")
		if not done_idx then
			return false
		end
		local inner = {}
		for i = 2, done_idx - 1 do
			inner[#inner + 1] = tokens[i]
		end
		exec_while(inner, true)
		return true
	elseif first == "for" then
		local done_idx = find_matching(tokens, 2, "done")
		if not done_idx then
			return false
		end
		if not done_idx then
			return false
		end
		local inner = {}
		for i = 2, done_idx - 1 do
			inner[#inner + 1] = tokens[i]
		end
		exec_for(inner)
		return true
	elseif first == "case" then
		-- case WORD in pattern) commands;; ... esac
		-- Find esac
		local esac_idx
		local depth = 0
		for i = 1, #tokens do
			if tokens[i] == "case" then depth = depth + 1
			elseif tokens[i] == "esac" then
				depth = depth - 1
				if depth == 0 then esac_idx = i; break end
			end
		end
		if not esac_idx then return false end
		-- tokens[2] = word, tokens[3] should be "in"
		local expand = require("sh.expand")
		local env = require("sh.env")
		local word = expand.word(tokens[2])
		-- Parse clauses between "in" and "esac"
		-- Each clause: pattern [| pattern]... ) commands ;;
		local i = 4 -- skip "case WORD in"
		if tokens[3] == "in" then i = 4
		else i = 3 end
		local matched = false
		while i < esac_idx and not matched do
			-- Collect patterns until )
			local patterns = {}
			while i < esac_idx and tokens[i] ~= ")" do
				if tokens[i] ~= "|" and tokens[i] ~= "(" then
					patterns[#patterns + 1] = tokens[i]
				end
				i = i + 1
			end
			i = i + 1 -- skip )
			-- Collect commands until ;; or esac
			local cmd_tokens = {}
			while i < esac_idx and tokens[i] ~= ";;" do
				cmd_tokens[#cmd_tokens + 1] = tokens[i]
				i = i + 1
			end
			if tokens[i] == ";;" then i = i + 1 end
			-- Check if word matches any pattern
			for _, pat in ipairs(patterns) do
				local epat = expand.word(pat)
				if M.case_match(word, epat) then
					matched = true
					if #cmd_tokens > 0 then
						run_cmd(tokens_to_string(cmd_tokens))
					end
					break
				end
			end
		end
		return true
	elseif first == "(" then
		-- Subshell: find matching )
		local depth = 0
		local close_idx
		for i = 1, #tokens do
			if tokens[i] == "(" then depth = depth + 1
			elseif tokens[i] == ")" then
				depth = depth - 1
				if depth == 0 then close_idx = i; break end
			end
		end
		if not close_idx then return false end
		local inner = {}
		for i = 2, close_idx - 1 do inner[#inner + 1] = tokens[i] end
		local body = tokens_to_string(inner)
		-- Fork and execute in child
		local unistd = require("posix.unistd")
		local wait = require("posix.sys.wait")
		local env = require("sh.env")
		local pid = unistd.fork()
		if pid == 0 then
			run_cmd(body)
			os.exit(tonumber(env.get("?")) or 0)
		end
		local _, reason, status = wait.wait(pid)
		if reason == "exited" then
			env.set_status(status)
		elseif reason == "killed" then
			env.set_status(128 + status)
		else
			env.set_status(1)
		end
		return true
	elseif first == "{" then
		-- Brace group: find matching }
		local depth = 0
		local close_idx
		for i = 1, #tokens do
			if tokens[i] == "{" then depth = depth + 1
			elseif tokens[i] == "}" then
				depth = depth - 1
				if depth == 0 then close_idx = i; break end
			end
		end
		if not close_idx then return false end
		local inner = {}
		for i = 2, close_idx - 1 do inner[#inner + 1] = tokens[i] end
		local body = tokens_to_string(inner)
		run_cmd(body)
		return true
	end

	return false
end

return M
