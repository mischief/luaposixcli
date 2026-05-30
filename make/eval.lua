-- SPDX-License-Identifier: ISC
-- make/eval.lua - variable expansion and evaluation engine for POSIX make
local M = {}

-- Variable flavors
local RECURSIVE = "recursive" -- = (expanded on use)
local SIMPLE = "simple" -- := or ::= (expanded on assignment)

-- Create a new variable environment
function M.new()
	local self = {
		vars = {}, -- name -> {value=string, flavor=string, origin=string}
		exported = {}, -- name -> true
	}
	return setmetatable(self, { __index = M })
end

-- Set a variable
function M:set(name, value, flavor, origin)
	self.vars[name] = { value = value, flavor = flavor or RECURSIVE, origin = origin or "file" }
end

-- Append to a variable (+=)
function M:append(name, value)
	local v = self.vars[name]
	if v then
		if v.value == "" then
			v.value = value
		else
			v.value = v.value .. " " .. value
		end
	else
		self:set(name, value, RECURSIVE)
	end
end

-- Conditional set (?=) - only set if not already defined
function M:set_if_absent(name, value)
	if not self.vars[name] then
		self:set(name, value, RECURSIVE)
	end
end

-- Get raw (unexpanded) value
function M:raw(name)
	local v = self.vars[name]
	return v and v.value or nil
end

-- Get expanded value
function M:get(name)
	local v = self.vars[name]
	if not v then return "" end
	if v.flavor == SIMPLE then return v.value end
	return self:expand(v.value)
end

-- Expand variable references in a string: $(VAR), ${VAR}, $X (single char)
-- Also handles: $(subst ...), $(patsubst ...), $(strip ...), $(shell ...)
function M:expand(s)
	if not s or s == "" then return "" end
	local result = {}
	local i = 1
	local len = #s
	while i <= len do
		local c = s:sub(i, i)
		if c == "$" then
			i = i + 1
			if i > len then result[#result + 1] = "$"; break end
			local nxt = s:sub(i, i)
			if nxt == "$" then
				result[#result + 1] = "$"
				i = i + 1
			elseif nxt == "(" or nxt == "{" then
				local close = nxt == "(" and ")" or "}"
				local depth = 1
				local start = i + 1
				i = i + 1
				while i <= len and depth > 0 do
					local ch = s:sub(i, i)
					if ch == nxt then depth = depth + 1
					elseif ch == close then depth = depth - 1 end
					i = i + 1
				end
				local ref = s:sub(start, i - 2)
				result[#result + 1] = self:expand_ref(ref)
			elseif nxt == "@" or nxt == "<" or nxt == "^" or nxt == "?"
				or nxt == "*" or nxt == "%" then
				-- Automatic variables (single char)
				result[#result + 1] = self:get(nxt)
				i = i + 1
			else
				-- Single-char variable name
				result[#result + 1] = self:get(nxt)
				i = i + 1
			end
		else
			result[#result + 1] = c
			i = i + 1
		end
	end
	return table.concat(result)
end

-- Expand a variable reference (content between $( and ))
-- Handles functions, D/F variants, substitution references
function M:expand_ref(ref)
	-- D/F variants of automatic macros: $(@D), $(@F), $(*D), $(*F), $(<D), $(<F), etc.
	local auto_var, variant = ref:match("^([@%%%*%<%^%?%+])([DF])$")
	if auto_var then
		local val = self:get(auto_var)
		if variant == "D" then
			-- Directory part of each word
			local words = {}
			for w in val:gmatch("%S+") do
				words[#words + 1] = w:match("^(.*/)") or "."
			end
			return table.concat(words, " ")
		else -- "F"
			-- File part of each word
			local words = {}
			for w in val:gmatch("%S+") do
				words[#words + 1] = w:match("([^/]+)$") or w
			end
			return table.concat(words, " ")
		end
	end

	-- Check for function call: word followed by space then args
	local func, args = ref:match("^(%S+)%s+(.*)")
	if func then
		if func == "shell" then return self:fn_shell(args)
		elseif func == "subst" then return self:fn_subst(args)
		elseif func == "patsubst" then return self:fn_patsubst(args)
		elseif func == "strip" then return self:fn_strip(args)
		elseif func == "wildcard" then return self:fn_wildcard(args)
		elseif func == "notdir" then return self:fn_notdir(args)
		elseif func == "dir" then return self:fn_dir(args)
		elseif func == "basename" then return self:fn_basename(args)
		elseif func == "suffix" then return self:fn_suffix(args)
		elseif func == "addprefix" then return self:fn_addprefix(args)
		elseif func == "addsuffix" then return self:fn_addsuffix(args)
		elseif func == "filter" then return self:fn_filter(args)
		elseif func == "filter-out" then return self:fn_filter_out(args)
		elseif func == "sort" then return self:fn_sort(args)
		elseif func == "word" then return self:fn_word(args)
		elseif func == "words" then return self:fn_words(args)
		elseif func == "firstword" then return self:fn_firstword(args)
		elseif func == "lastword" then return self:fn_lastword(args)
		end
	end

	-- Substitution reference: $(VAR:old=new) or $(VAR:%old=%new)
	local varname, old, new = ref:match("^([^:]+):(.-)=(.*)$")
	if varname then
		local val = self:get(varname)
		old = self:expand(old)
		new = self:expand(new)
		-- Check for pattern substitution (% wildcard)
		if old:find("%%") then
			local words = {}
			for w in val:gmatch("%S+") do
				words[#words + 1] = M.patsubst_word(old, new, w)
			end
			return table.concat(words, " ")
		end
		-- Simple suffix substitution
		local escaped_old = old:gsub("([%.%+%-%*%?%[%]%^%$%(%)%%])", "%%%1")
		local words = {}
		for w in val:gmatch("%S+") do
			words[#words + 1] = w:gsub(escaped_old .. "$", new)
		end
		return table.concat(words, " ")
	end

	-- Plain variable reference
	local expanded_name = self:expand(ref)
	return self:get(expanded_name)
end

-- Split comma-separated function args (respecting nested $(...))
function M:split_args(s)
	local args = {}
	local depth = 0
	local current = {}
	local i = 1
	while i <= #s do
		local c = s:sub(i, i)
		if c == "," and depth == 0 then
			args[#args + 1] = table.concat(current)
			current = {}
		elseif c == "(" or c == "{" then
			depth = depth + 1
			current[#current + 1] = c
		elseif c == ")" or c == "}" then
			depth = depth - 1
			current[#current + 1] = c
		else
			current[#current + 1] = c
		end
		i = i + 1
	end
	args[#args + 1] = table.concat(current)
	return args
end

-- $(shell cmd)
function M:fn_shell(args)
	local cmd = self:expand(args)
	local f = io.popen(cmd, "r")
	if not f then return "" end
	local out = f:read("*a")
	f:close()
	-- Replace newlines with spaces, strip trailing
	return (out:gsub("\n+$", ""):gsub("\n", " "))
end

-- $(subst from,to,text)
function M:fn_subst(args)
	local parts = self:split_args(args)
	if #parts < 3 then return "" end
	local from = self:expand(parts[1])
	local to = self:expand(parts[2])
	local text = self:expand(parts[3])
	return (text:gsub(from:gsub("([%.%+%-%*%?%[%]%^%$%(%)%%])", "%%%1"), to))
end

-- $(patsubst pattern,replacement,text)
function M:fn_patsubst(args)
	local parts = self:split_args(args)
	if #parts < 3 then return "" end
	local pat = self:expand(parts[1])
	local repl = self:expand(parts[2])
	local text = self:expand(parts[3])
	local words = {}
	for w in text:gmatch("%S+") do
		words[#words + 1] = M.patsubst_word(pat, repl, w)
	end
	return table.concat(words, " ")
end

-- Apply a single patsubst to a word
function M.patsubst_word(pat, repl, word)
	local pre, suf = pat:match("^(.-)%%(.*)$")
	if not pre then
		-- No %, exact match
		return word == pat and repl or word
	end
	if word:sub(1, #pre) == pre and word:sub(-#suf) == suf and #word >= #pre + #suf then
		local stem = word:sub(#pre + 1, #word - #suf)
		return (repl:gsub("%%", stem))
	end
	return word
end

-- $(strip text)
function M:fn_strip(args)
	local text = self:expand(args)
	return (text:match("^%s*(.-)%s*$"):gsub("%s+", " "))
end

-- $(wildcard pattern)
function M:fn_wildcard(args)
	local pat = self:expand(args)
	local posix_glob = require("posix.glob")
	local results = {}
	for p in pat:gmatch("%S+") do
		local matches = posix_glob.glob(p, 0)
		if matches then
			for _, m in ipairs(matches) do results[#results + 1] = m end
		end
	end
	return table.concat(results, " ")
end

-- $(notdir names)
function M:fn_notdir(args)
	local text = self:expand(args)
	local words = {}
	for w in text:gmatch("%S+") do
		words[#words + 1] = w:match("([^/]+)$") or ""
	end
	return table.concat(words, " ")
end

-- $(dir names)
function M:fn_dir(args)
	local text = self:expand(args)
	local words = {}
	for w in text:gmatch("%S+") do
		words[#words + 1] = w:match("^(.*/)") or "./"
	end
	return table.concat(words, " ")
end

-- $(basename names)
function M:fn_basename(args)
	local text = self:expand(args)
	local words = {}
	for w in text:gmatch("%S+") do
		words[#words + 1] = w:match("^(.+)%..+$") or w
	end
	return table.concat(words, " ")
end

-- $(suffix names)
function M:fn_suffix(args)
	local text = self:expand(args)
	local words = {}
	for w in text:gmatch("%S+") do
		local s = w:match("(%.[^./]+)$")
		if s then words[#words + 1] = s end
	end
	return table.concat(words, " ")
end

-- $(addprefix prefix,names)
function M:fn_addprefix(args)
	local parts = self:split_args(args)
	if #parts < 2 then return "" end
	local prefix = self:expand(parts[1])
	local text = self:expand(parts[2])
	local words = {}
	for w in text:gmatch("%S+") do words[#words + 1] = prefix .. w end
	return table.concat(words, " ")
end

-- $(addsuffix suffix,names)
function M:fn_addsuffix(args)
	local parts = self:split_args(args)
	if #parts < 2 then return "" end
	local suffix = self:expand(parts[1])
	local text = self:expand(parts[2])
	local words = {}
	for w in text:gmatch("%S+") do words[#words + 1] = w .. suffix end
	return table.concat(words, " ")
end

-- $(filter pattern,text)
function M:fn_filter(args)
	local parts = self:split_args(args)
	if #parts < 2 then return "" end
	local pats = {}
	for p in self:expand(parts[1]):gmatch("%S+") do pats[#pats + 1] = p end
	local text = self:expand(parts[2])
	local words = {}
	for w in text:gmatch("%S+") do
		for _, p in ipairs(pats) do
			if M.pattern_match(p, w) then words[#words + 1] = w; break end
		end
	end
	return table.concat(words, " ")
end

-- $(filter-out pattern,text)
function M:fn_filter_out(args)
	local parts = self:split_args(args)
	if #parts < 2 then return "" end
	local pats = {}
	for p in self:expand(parts[1]):gmatch("%S+") do pats[#pats + 1] = p end
	local text = self:expand(parts[2])
	local words = {}
	for w in text:gmatch("%S+") do
		local matched = false
		for _, p in ipairs(pats) do
			if M.pattern_match(p, w) then matched = true; break end
		end
		if not matched then words[#words + 1] = w end
	end
	return table.concat(words, " ")
end

-- $(sort list)
function M:fn_sort(args)
	local text = self:expand(args)
	local words = {}
	local seen = {}
	for w in text:gmatch("%S+") do
		if not seen[w] then seen[w] = true; words[#words + 1] = w end
	end
	table.sort(words)
	return table.concat(words, " ")
end

-- $(word n,text)
function M:fn_word(args)
	local parts = self:split_args(args)
	if #parts < 2 then return "" end
	local n = tonumber(self:expand(parts[1])) or 0
	local text = self:expand(parts[2])
	local i = 0
	for w in text:gmatch("%S+") do
		i = i + 1
		if i == n then return w end
	end
	return ""
end

-- $(words text)
function M:fn_words(args)
	local text = self:expand(args)
	local n = 0
	for _ in text:gmatch("%S+") do n = n + 1 end
	return tostring(n)
end

-- $(firstword text)
function M:fn_firstword(args)
	local text = self:expand(args)
	return text:match("%S+") or ""
end

-- $(lastword text)
function M:fn_lastword(args)
	local text = self:expand(args)
	local last = ""
	for w in text:gmatch("%S+") do last = w end
	return last
end

-- Pattern matching: % is wildcard
function M.pattern_match(pat, word)
	local pre, suf = pat:match("^(.-)%%(.*)$")
	if not pre then return pat == word end
	if #word < #pre + #suf then return false end
	return word:sub(1, #pre) == pre and word:sub(-#suf) == suf
end

-- Extract stem from pattern match
function M.pattern_stem(pat, word)
	local pre, suf = pat:match("^(.-)%%(.*)$")
	if not pre then return word == pat and "" or nil end
	if #word < #pre + #suf then return nil end
	if word:sub(1, #pre) == pre and (#suf == 0 or word:sub(-#suf) == suf) then
		return word:sub(#pre + 1, #word - #suf)
	end
	return nil
end

-- Process parsed nodes into the environment, evaluating assignments and conditionals
function M:load(nodes)
	self:process_nodes(nodes, 1, #nodes)
end

function M:process_nodes(nodes, start, stop)
	local i = start
	while i <= stop do
		local node = nodes[i]
		if node.type == "assign" then
			self:process_assign(node)
		elseif node.type == "conditional" then
			i = self:process_conditional(nodes, i)
		-- Other node types (rule, include, etc.) are handled by exec
		end
		i = i + 1
	end
end

function M:process_assign(node)
	local op = node.op
	if op == "=" then
		self:set(node.name, node.value, RECURSIVE, "file")
	elseif op == ":=" or op == "::=" then
		self:set(node.name, self:expand(node.value), SIMPLE, "file")
	elseif op == "+=" then
		self:append(node.name, node.value)
	elseif op == "?=" then
		self:set_if_absent(node.name, node.value)
	elseif op == "!=" then
		-- Shell assignment
		local cmd = self:expand(node.value)
		local f = io.popen(cmd, "r")
		local out = f and f:read("*a") or ""
		if f then f:close() end
		self:set(node.name, (out:gsub("\n+$", ""):gsub("\n", " ")), SIMPLE, "file")
	end
end

function M:process_conditional(nodes, idx)
	local node = nodes[idx]
	local cond = self:eval_condition(node)
	-- Find matching else/endif, respecting nesting
	local depth = 1
	local else_idx = nil
	local endif_idx = nil
	local j = idx + 1
	while j <= #nodes do
		local n = nodes[j]
		if n.type == "conditional" then
			depth = depth + 1
		elseif n.type == "else" and depth == 1 then
			else_idx = j
		elseif n.type == "endif" then
			depth = depth - 1
			if depth == 0 then endif_idx = j; break end
		end
		j = j + 1
	end
	if not endif_idx then return #nodes end -- malformed, skip to end

	if cond then
		local stop = (else_idx or endif_idx) - 1
		self:process_nodes(nodes, idx + 1, stop)
	elseif else_idx then
		self:process_nodes(nodes, else_idx + 1, endif_idx - 1)
	end
	return endif_idx
end

function M:eval_condition(node)
	local kw = node.keyword
	local arg = node.arg
	if kw == "ifdef" then
		local name = arg:match("^%s*(%S+)")
		return self:raw(name) ~= nil
	elseif kw == "ifndef" then
		local name = arg:match("^%s*(%S+)")
		return self:raw(name) == nil
	elseif kw == "ifeq" then
		local a, b = self:parse_condition_args(arg)
		return self:expand(a) == self:expand(b)
	elseif kw == "ifneq" then
		local a, b = self:parse_condition_args(arg)
		return self:expand(a) ~= self:expand(b)
	end
	return false
end

-- Parse ifeq/ifneq args: (a,b) or "a" "b" or 'a' 'b'
function M:parse_condition_args(arg)
	-- (a,b) form
	local a, b = arg:match("^%((.+),(.+)%)$")
	if a then return a:match("^%s*(.-)%s*$"), b:match("^%s*(.-)%s*$") end
	-- "a" "b" or 'a' 'b' form
	a, b = arg:match('^"(.-)".-"(.-)"')
	if a then return a, b end
	a, b = arg:match("^'(.-)'.-'(.-)'")
	if a then return a, b end
	return "", ""
end

-- Seed environment variables (POSIX: SHELL env var is NOT imported)
function M:seed_env()
	for k, v in pairs(require("posix.stdlib").getenv()) do
		if type(k) == "string" and k ~= "SHELL" then
			if not self.vars[k] then
				self:set(k, v, RECURSIVE, "environment")
			end
		end
	end
end

-- Set default POSIX variables
function M:set_defaults()
	self:set_if_absent("SHELL", "/bin/sh")
	self:set_if_absent("CC", "c99")
	self:set_if_absent("CFLAGS", "")
	self:set_if_absent("LDFLAGS", "")
	self:set_if_absent("AR", "ar")
	self:set_if_absent("ARFLAGS", "-rv")
	self:set_if_absent("YACC", "yacc")
	self:set_if_absent("YFLAGS", "")
	self:set_if_absent("LEX", "lex")
	self:set_if_absent("LFLAGS", "")
	self:set_if_absent("GET", "get")
	self:set_if_absent("GFLAGS", "")
end

return M
