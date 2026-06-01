-- SPDX-License-Identifier: ISC
-- awk/eval.lua - AST interpreter for POSIX awk
local M = {}

-- Signals for flow control
local BREAK = {}
local CONTINUE = {}
local NEXT = {}
local EXIT = {}
local RETURN = {}

-- Create a new interpreter state
function M.new()
	local self = {}
	self.globals = {}
	self.functions = {}
	self.fields = {}
	self.nr = 0
	self.fnr = 0
	self.nf = 0
	self.record = ""
	self.ofs = " "
	self.ors = "\n"
	self.fs = " "
	self.rs = "\n"
	self.ofmt = "%.6g"
	self.convfmt = "%.6g"
	self.subsep = "\034"
	self.rstart = 0
	self.rlength = -1
	self.filename = ""
	self.output_files = {}
	self.output_pipes = {}
	self.input_pipes = {}
	self.rand_seed = os.time()
	self.environ = {}
	self.regex_cache = {}

	-- Load notposix for POSIX regex support
	local ok, np = pcall(require, "luaposixcli.sys")
	if ok then
		self.notposix = np
	end
	for _, kv in ipairs(require("posix.stdlib").getenv()) do
		-- getenv returns table of "KEY=VALUE" strings in some versions
	end
	-- populate ENVIRON from os
	local ok, stdlib = pcall(require, "posix.stdlib")
	if ok and stdlib.getenv then
		-- luaposix getenv() with no args returns a table
		local env = stdlib.getenv()
		if type(env) == "table" then
			for k, v in pairs(env) do
				if type(k) == "string" then self.environ[k] = v end
			end
		end
	end

	-- Output function (can be overridden for testing)
	self.write = function(s) io.write(s) end
	self.write_err = function(s) io.stderr:write(s) end

	return setmetatable(self, { __index = M })
end

-- Convert awk value to number
-- Match string against an ERE pattern. Returns (start, end) 1-indexed or nil.
-- Uses notposix POSIX regex if available, falls back to Lua patterns.
function M:regex_find(str, pat)
	if self.notposix then
		if not self.regex_cache[pat] then
			self.regex_cache[pat] = self.notposix.regcomp(pat, self.notposix.REG_EXTENDED)
		end
		local m = self.regex_cache[pat]:exec(str)
		if m then return m[1][1], m[1][2] end
		return nil
	end
	-- Fallback: try Lua pattern (limited)
	return str:find(pat)
end

-- Extract a regex pattern string from an expression node.
-- ERE nodes use their value directly; other expressions are evaluated and converted to string.
function M:get_pat(node, locals)
	if node.type == "ere" then return node.value end
	return M.to_string(self, self:eval_expr(node, locals))
end

-- Match and replace using ERE. Returns new string and count of replacements.
function M:regex_sub(str, pat, repl_fn, global)
	if self.notposix then
		if not self.regex_cache[pat] then
			self.regex_cache[pat] = self.notposix.regcomp(pat, self.notposix.REG_EXTENDED)
		end
		local re = self.regex_cache[pat]
		local result = {}
		local count = 0
		local pos = 1
		while pos <= #str do
			local m = re:exec(str:sub(pos))
			if not m then result[#result + 1] = str:sub(pos); break end
			local s, e = m[1][1], m[1][2]
			result[#result + 1] = str:sub(pos, pos + s - 2)
			local matched = str:sub(pos + s - 1, pos + e - 1)
			result[#result + 1] = repl_fn(matched)
			count = count + 1
			local advance = e
			if e < s then advance = s end -- zero-length match
			pos = pos + advance
			if not global then result[#result + 1] = str:sub(pos); break end
		end
		return table.concat(result), count
	end
	-- Fallback
	if global then
		local r, n = str:gsub(pat, repl_fn)
		return r, n
	else
		local r, n = str:gsub(pat, repl_fn, 1)
		return r, n
	end
end

function M.to_number(v)
	if type(v) == "number" then return v end
	if type(v) == "string" then return tonumber(v:match("^%s*[+-]?%d*%.?%d*[eE]?[+-]?%d*")) or 0 end
	return 0
end

-- Convert awk value to string
function M.to_string(self, v)
	if type(v) == "string" then return v end
	if type(v) == "number" then
		if v == math.floor(v) and v >= -2147483648 and v <= 2147483647 then
			return string.format("%d", v)
		end
		return string.format(self.convfmt, v)
	end
	return ""
end

-- Is value truthy in boolean context?
-- Numeric 0 is false, non-empty strings are true unless they're numeric strings equal to 0
function M.is_true(v)
	if type(v) == "number" then return v ~= 0 end
	if type(v) == "string" then
		if v == "" then return false end
		local n = tonumber(v)
		if n then return n ~= 0 end
		return true
	end
	return false
end

-- Get a global variable value
function M:get_var(name)
	if name == "NR" then return self.nr
	elseif name == "NF" then return self.nf
	elseif name == "FNR" then return self.fnr
	elseif name == "FS" then return self.fs
	elseif name == "RS" then return self.rs
	elseif name == "OFS" then return self.ofs
	elseif name == "ORS" then return self.ors
	elseif name == "OFMT" then return self.ofmt
	elseif name == "CONVFMT" then return self.convfmt
	elseif name == "SUBSEP" then return self.subsep
	elseif name == "RSTART" then return self.rstart
	elseif name == "RLENGTH" then return self.rlength
	elseif name == "FILENAME" then return self.filename
	elseif name == "NR" then return self.nr
	elseif name == "ARGC" then return self.globals["ARGC"] or 0
	elseif name == "ENVIRON" then return self.environ
	elseif name == "ARGV" then return self.globals["ARGV"] or {}
	end
	local v = self.globals[name]
	if v == nil then return "" end
	return v
end

-- Set a global variable
function M:set_var(name, val)
	if name == "NR" then self.nr = M.to_number(val)
	elseif name == "NF" then
		self.nf = math.floor(M.to_number(val))
		self:rebuild_record()
	elseif name == "FNR" then self.fnr = M.to_number(val)
	elseif name == "FS" then self.fs = M.to_string(self, val)
	elseif name == "RS" then self.rs = M.to_string(self, val)
	elseif name == "OFS" then self.ofs = M.to_string(self, val)
	elseif name == "ORS" then self.ors = M.to_string(self, val)
	elseif name == "OFMT" then self.ofmt = M.to_string(self, val)
	elseif name == "CONVFMT" then self.convfmt = M.to_string(self, val)
	elseif name == "SUBSEP" then self.subsep = M.to_string(self, val)
	else
		self.globals[name] = val
	end
end

-- Get field $n
function M:get_field(n)
	n = math.floor(M.to_number(n))
	if n == 0 then return self.record end
	if n < 0 then return "" end
	return self.fields[n] or ""
end

-- Set field $n
function M:set_field(n, val)
	n = math.floor(M.to_number(n))
	if n == 0 then
		self.record = M.to_string(self, val)
		self:split_record()
		return
	end
	if n > self.nf then
		for i = self.nf + 1, n - 1 do self.fields[i] = "" end
		self.nf = n
	end
	self.fields[n] = M.to_string(self, val)
	self:rebuild_record()
end

-- Split $0 into fields based on FS
function M:split_record()
	self.fields = {}
	if self.fs == " " then
		local i = 0
		for f in self.record:gmatch("%S+") do
			i = i + 1
			self.fields[i] = f
		end
		self.nf = i
	elseif #self.fs == 1 then
		local i = 0
		if self.record == "" then
			self.nf = 0
			return
		end
		for f in (self.record .. self.fs):gmatch("([^" .. self.fs:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1") .. "]*)" .. self.fs:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")) do
			i = i + 1
			self.fields[i] = f
		end
		self.nf = i
	else
		-- ERE field separator
		local rec = self.record
		local i = 0
		if rec == "" then self.nf = 0; return end
		while true do
			local s, e = rec:find(self.fs)
			if not s then
				i = i + 1; self.fields[i] = rec; break
			end
			i = i + 1; self.fields[i] = rec:sub(1, s - 1)
			rec = rec:sub(e + 1)
		end
		self.nf = i
	end
end

-- Rebuild $0 from fields using OFS
function M:rebuild_record()
	local parts = {}
	for i = 1, self.nf do parts[i] = self.fields[i] or "" end
	self.record = table.concat(parts, self.ofs)
end

-- Evaluate an AST expression node, returning its value
function M:eval_expr(node, locals)
	local t = node.type
	if t == "number" then return node.value
	elseif t == "string" then return node.value
	elseif t == "ere" then
		-- ERE in expression context means $0 ~ /ere/
		local pat = node.value
		return self:regex_find(self.record, pat) and 1 or 0
	elseif t == "name" then
		if locals and locals[node.name] ~= nil then return locals[node.name] end
		return self:get_var(node.name)
	elseif t == "field" then
		return self:get_field(self:eval_expr(node.expr, locals))
	elseif t == "index" then
		local arr = self:get_array(node.array, locals)
		local idx = self:make_index(node.indices, locals)
		local v = arr[idx]
		return v == nil and "" or v
	elseif t == "unary" then
		local v = self:eval_expr(node.expr, locals)
		if node.op == "-" then return -M.to_number(v)
		elseif node.op == "+" then return M.to_number(v)
		elseif node.op == "!" then return M.is_true(v) and 0 or 1
		end
	elseif t == "binary" then
		return self:eval_binary(node, locals)
	elseif t == "concat" then
		return M.to_string(self, self:eval_expr(node.left, locals)) .. M.to_string(self, self:eval_expr(node.right, locals))
	elseif t == "assign" then
		return self:eval_assign(node, locals)
	elseif t == "incr" or t == "decr" then
		return self:eval_incdec(node, locals)
	elseif t == "ternary" then
		if M.is_true(self:eval_expr(node.cond, locals)) then
			return self:eval_expr(node.then_, locals)
		else
			return self:eval_expr(node.else_, locals)
		end
	elseif t == "in" then
		local arr = self:get_array(node.array, locals)
		local idx = self:make_index(node.index, locals)
		return arr[idx] ~= nil and 1 or 0
	elseif t == "call" then
		return self:eval_call(node, locals)
	elseif t == "getline" then
		return self:eval_getline(node, locals)
	elseif t == "group" then
		-- parenthesized expr list - return last
		local v
		for _, e in ipairs(node.exprs) do v = self:eval_expr(e, locals) end
		return v
	end
	return ""
end

-- Get or create an array (from globals or locals)
function M:get_array(name, locals)
	if locals and type(locals[name]) == "table" then return locals[name] end
	local v = self.globals[name]
	if type(v) ~= "table" then v = {}; self.globals[name] = v end
	return v
end

-- Build a SUBSEP-joined index from a list of expression nodes
function M:make_index(indices, locals)
	if #indices == 1 then
		return M.to_string(self, self:eval_expr(indices[1], locals))
	end
	local parts = {}
	for i, e in ipairs(indices) do parts[i] = M.to_string(self, self:eval_expr(e, locals)) end
	return table.concat(parts, self.subsep)
end

-- Evaluate binary operations
function M:eval_binary(node, locals)
	local op = node.op
	-- Short-circuit logical operators
	if op == "&&" then
		return (M.is_true(self:eval_expr(node.left, locals)) and M.is_true(self:eval_expr(node.right, locals))) and 1 or 0
	elseif op == "||" then
		return (M.is_true(self:eval_expr(node.left, locals)) or M.is_true(self:eval_expr(node.right, locals))) and 1 or 0
	end

	-- Regex match: get pattern from raw node (ERE nodes must not be evaluated as expressions)
	if op == "~" then
		local s = M.to_string(self, self:eval_expr(node.left, locals))
		local pat = self:get_pat(node.right, locals)
		return self:regex_find(s, pat) and 1 or 0
	elseif op == "!~" then
		local s = M.to_string(self, self:eval_expr(node.left, locals))
		local pat = self:get_pat(node.right, locals)
		return self:regex_find(s, pat) and 0 or 1
	end

	local lv = self:eval_expr(node.left, locals)
	local rv = self:eval_expr(node.right, locals)

	-- Comparison: numeric if both numeric or numeric strings
	if op == "<" or op == "<=" or op == "==" or op == "!=" or op == ">=" or op == ">" then
		local ln, rn = tonumber(lv), tonumber(rv)
		local numeric = (type(lv) == "number" or ln) and (type(rv) == "number" or rn)
		if numeric then
			ln = ln or M.to_number(lv)
			rn = rn or M.to_number(rv)
			if op == "<" then return ln < rn and 1 or 0
			elseif op == "<=" then return ln <= rn and 1 or 0
			elseif op == "==" then return ln == rn and 1 or 0
			elseif op == "!=" then return ln ~= rn and 1 or 0
			elseif op == ">=" then return ln >= rn and 1 or 0
			elseif op == ">" then return ln > rn and 1 or 0
			end
		else
			local ls = M.to_string(self, lv)
			local rs = M.to_string(self, rv)
			if op == "<" then return ls < rs and 1 or 0
			elseif op == "<=" then return ls <= rs and 1 or 0
			elseif op == "==" then return ls == rs and 1 or 0
			elseif op == "!=" then return ls ~= rs and 1 or 0
			elseif op == ">=" then return ls >= rs and 1 or 0
			elseif op == ">" then return ls > rs and 1 or 0
			end
		end
	end

	-- Arithmetic
	local ln = M.to_number(lv)
	local rn = M.to_number(rv)
	if op == "+" then return ln + rn
	elseif op == "-" then return ln - rn
	elseif op == "*" then return ln * rn
	elseif op == "/" then return rn == 0 and 0 or ln / rn
	elseif op == "%" then return rn == 0 and 0 or math.fmod(ln, rn)
	elseif op == "^" then return ln ^ rn
	end
	return 0
end

-- Evaluate assignment (=, +=, -=, etc.)
function M:eval_assign(node, locals)
	local val = self:eval_expr(node.value, locals)
	if node.op ~= "=" then
		local cur = self:eval_lvalue(node.target, locals)
		local cn = M.to_number(cur)
		local vn = M.to_number(val)
		if node.op == "+=" then val = cn + vn
		elseif node.op == "-=" then val = cn - vn
		elseif node.op == "*=" then val = cn * vn
		elseif node.op == "/=" then val = vn == 0 and 0 or cn / vn
		elseif node.op == "%=" then val = vn == 0 and 0 or math.fmod(cn, vn)
		elseif node.op == "^=" then val = cn ^ vn
		end
	end
	self:set_lvalue(node.target, val, locals)
	return val
end

-- Read the current value of an lvalue
function M:eval_lvalue(node, locals)
	if node.type == "name" then
		if locals and locals[node.name] ~= nil then return locals[node.name] end
		return self:get_var(node.name)
	elseif node.type == "field" then
		return self:get_field(self:eval_expr(node.expr, locals))
	elseif node.type == "index" then
		local arr = self:get_array(node.array, locals)
		local idx = self:make_index(node.indices, locals)
		return arr[idx] or ""
	end
	return ""
end

-- Set an lvalue to a value
function M:set_lvalue(node, val, locals)
	if node.type == "name" then
		if locals and locals[node.name] ~= nil then
			locals[node.name] = val
		else
			self:set_var(node.name, val)
		end
	elseif node.type == "field" then
		self:set_field(self:eval_expr(node.expr, locals), val)
	elseif node.type == "index" then
		local arr = self:get_array(node.array, locals)
		local idx = self:make_index(node.indices, locals)
		arr[idx] = val
	end
end

-- Evaluate ++/-- (pre and post)
function M:eval_incdec(node, locals)
	local cur = M.to_number(self:eval_lvalue(node.expr, locals))
	local delta = node.type == "incr" and 1 or -1
	local new = cur + delta
	self:set_lvalue(node.expr, new, locals)
	return node.pre and new or cur
end

-- Execute a statement node. Returns a signal (BREAK/CONTINUE/NEXT/EXIT/RETURN) or nil.
function M:exec_stmt(node, locals)
	if not node then return nil end
	local t = node.type

	if t == "block" then
		for _, stmt in ipairs(node.stmts) do
			local sig = self:exec_stmt(stmt, locals)
			if sig then return sig end
		end
	elseif t == "if" then
		if M.is_true(self:eval_expr(node.cond, locals)) then
			return self:exec_stmt(node.then_, locals)
		elseif node.else_ then
			return self:exec_stmt(node.else_, locals)
		end
	elseif t == "while" then
		while M.is_true(self:eval_expr(node.cond, locals)) do
			local sig = self:exec_stmt(node.body, locals)
			if sig == BREAK then break
			elseif sig == CONTINUE then -- continue
			elseif sig then return sig end
		end
	elseif t == "do_while" then
		repeat
			local sig = self:exec_stmt(node.body, locals)
			if sig == BREAK then break
			elseif sig == CONTINUE then -- continue
			elseif sig then return sig end
		until not M.is_true(self:eval_expr(node.cond, locals))
	elseif t == "for" then
		if node.init then self:exec_stmt(node.init, locals) end
		while not node.cond or M.is_true(self:eval_expr(node.cond, locals)) do
			local sig = self:exec_stmt(node.body, locals)
			if sig == BREAK then break
			elseif sig == CONTINUE then -- continue
			elseif sig then return sig end
			if node.step then self:exec_stmt(node.step, locals) end
		end
	elseif t == "for_in" then
		local arr = self:get_array(node.array, locals)
		for k, _ in pairs(arr) do
			if locals and locals[node.var] ~= nil then
				locals[node.var] = k
			else
				self:set_var(node.var, k)
			end
			local sig = self:exec_stmt(node.body, locals)
			if sig == BREAK then break
			elseif sig == CONTINUE then -- continue
			elseif sig then return sig end
		end
	elseif t == "break" then return BREAK
	elseif t == "continue" then return CONTINUE
	elseif t == "next" then return NEXT
	elseif t == "exit" then
		self.exit_code = node.expr and math.floor(M.to_number(self:eval_expr(node.expr, locals))) or 0
		return EXIT
	elseif t == "return" then
		self.return_value = node.expr and self:eval_expr(node.expr, locals) or ""
		return RETURN
	elseif t == "delete" then
		if node.target.type == "index" then
			local arr = self:get_array(node.target.array, locals)
			local idx = self:make_index(node.target.indices, locals)
			arr[idx] = nil
		elseif node.target.type == "name" then
			-- delete entire array
			if locals and locals[node.target.name] ~= nil then
				locals[node.target.name] = {}
			else
				self.globals[node.target.name] = {}
			end
		end
	elseif t == "print" then
		self:exec_print(node, locals)
	elseif t == "printf" then
		self:exec_printf(node, locals)
	else
		-- expression statement
		self:eval_expr(node, locals)
	end
	return nil
end

-- Get output handle for redirection
function M:get_output(redir)
	if not redir then return self.write end
	local target = M.to_string(self, redir.expr)
	if redir.redir == "|" then
		if not self.output_pipes[target] then
			self.output_pipes[target] = io.popen(target, "w")
		end
		return function(s) self.output_pipes[target]:write(s) end
	else
		if not self.output_files[target] then
			local mode = redir.redir == ">>" and "a" or "w"
			self.output_files[target] = io.open(target, mode)
		end
		return function(s) self.output_files[target]:write(s) end
	end
end

-- Execute print statement
function M:exec_print(node, locals)
	local out = self:get_output(node.output and { redir = node.output.redir, expr = self:eval_expr(node.output.expr, locals) } or nil)
	if #node.args == 0 then
		out(self.record .. self.ors)
	else
		local parts = {}
		for i, arg in ipairs(node.args) do
			parts[i] = M.to_string(self, self:eval_expr(arg, locals))
		end
		out(table.concat(parts, self.ofs) .. self.ors)
	end
end

-- Execute printf statement
function M:exec_printf(node, locals)
	if #node.args == 0 then return end
	local out = self:get_output(node.output and { redir = node.output.redir, expr = self:eval_expr(node.output.expr, locals) } or nil)
	local fmt = M.to_string(self, self:eval_expr(node.args[1], locals))
	local args = {}
	for i = 2, #node.args do args[i - 1] = self:eval_expr(node.args[i], locals) end
	out(self:awk_sprintf(fmt, args))
end

-- awk sprintf implementation
function M:awk_sprintf(fmt, args)
	local result = {}
	local ai = 1
	local i = 1
	while i <= #fmt do
		local c = fmt:sub(i, i)
		if c == "%" then
			-- parse format spec
			local start = i
			i = i + 1
			if i > #fmt then result[#result + 1] = "%"; break end
			if fmt:sub(i, i) == "%" then
				result[#result + 1] = "%"; i = i + 1
			else
				-- flags
				while i <= #fmt and fmt:sub(i, i):find("[%- +#0]") do i = i + 1 end
				-- width
				if i <= #fmt and fmt:sub(i, i) == "*" then
					i = i + 1
				else
					while i <= #fmt and fmt:sub(i, i):find("%d") do i = i + 1 end
				end
				-- precision
				if i <= #fmt and fmt:sub(i, i) == "." then
					i = i + 1
					if i <= #fmt and fmt:sub(i, i) == "*" then
						i = i + 1
					else
						while i <= #fmt and fmt:sub(i, i):find("%d") do i = i + 1 end
					end
				end
				-- conversion
				local conv = fmt:sub(i, i)
				local spec = fmt:sub(start, i)
				i = i + 1
				local arg = args[ai] or ""; ai = ai + 1
				if conv == "d" or conv == "i" then
					result[#result + 1] = string.format(spec, math.floor(M.to_number(arg)))
				elseif conv == "o" or conv == "x" or conv == "X" then
					result[#result + 1] = string.format(spec, math.floor(M.to_number(arg)))
				elseif conv == "f" or conv == "e" or conv == "E" or conv == "g" or conv == "G" then
					result[#result + 1] = string.format(spec, M.to_number(arg))
				elseif conv == "s" then
					result[#result + 1] = string.format(spec, M.to_string(self, arg))
				elseif conv == "c" then
					if type(arg) == "number" or tonumber(arg) then
						result[#result + 1] = string.char(math.floor(M.to_number(arg)))
					else
						result[#result + 1] = M.to_string(self, arg):sub(1, 1)
					end
				else
					result[#result + 1] = spec
				end
			end
		elseif c == "\\" then
			i = i + 1
			local e = fmt:sub(i, i)
			if e == "n" then result[#result + 1] = "\n"
			elseif e == "t" then result[#result + 1] = "\t"
			elseif e == "r" then result[#result + 1] = "\r"
			elseif e == "\\" then result[#result + 1] = "\\"
			elseif e == "a" then result[#result + 1] = "\a"
			elseif e == "b" then result[#result + 1] = "\b"
			elseif e == "f" then result[#result + 1] = "\f"
			elseif e == "/" then result[#result + 1] = "/"
			else result[#result + 1] = "\\" .. e end
			i = i + 1
		else
			result[#result + 1] = c
			i = i + 1
		end
	end
	return table.concat(result)
end

-- Evaluate builtin and user function calls
function M:eval_call(node, locals)
	local name = node.func
	local args = node.args

	-- Builtin functions
	if name == "length" then
		if #args == 0 then return #self.record end
		local v = self:eval_expr(args[1], locals)
		if type(v) == "table" then
			local n = 0; for _ in pairs(v) do n = n + 1 end; return n
		end
		return #M.to_string(self, v)
	elseif name == "substr" then
		local s = M.to_string(self, self:eval_expr(args[1], locals))
		local m = math.floor(M.to_number(self:eval_expr(args[2], locals)))
		if m < 1 then m = 1 end
		if #args >= 3 then
			local n = math.floor(M.to_number(self:eval_expr(args[3], locals)))
			return s:sub(m, m + n - 1)
		end
		return s:sub(m)
	elseif name == "index" then
		local s = M.to_string(self, self:eval_expr(args[1], locals))
		local t = M.to_string(self, self:eval_expr(args[2], locals))
		local pos = s:find(t, 1, true)
		return pos or 0
	elseif name == "split" then
		local s = M.to_string(self, self:eval_expr(args[1], locals))
		local arr_name = args[2].type == "name" and args[2].name or args[2].array
		local arr = self:get_array(arr_name, locals)
		-- clear array
		for k in pairs(arr) do arr[k] = nil end
		local fs = #args >= 3 and self:get_pat(args[3], locals) or self.fs
		local n = 0
		if fs == " " then
			for f in s:gmatch("%S+") do n = n + 1; arr[tostring(n)] = f end
		elseif #fs == 1 then
			if s == "" then return 0 end
			for f in (s .. fs):gmatch("([^" .. fs:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1") .. "]*)" .. fs:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")) do
				n = n + 1; arr[tostring(n)] = f
			end
		else
			if s == "" then return 0 end
			while true do
				local a, b = s:find(fs)
				if not a then n = n + 1; arr[tostring(n)] = s; break end
				n = n + 1; arr[tostring(n)] = s:sub(1, a - 1)
				s = s:sub(b + 1)
			end
		end
		return n
	elseif name == "sub" or name == "gsub" then
		local pat = self:get_pat(args[1], locals)
		local repl = M.to_string(self, self:eval_expr(args[2], locals))
		local target_node = args[3]
		local s
		if target_node then
			s = M.to_string(self, self:eval_lvalue(target_node, locals))
		else
			s = self.record
		end
		-- Build replacement function that handles & and \&
		local function repl_fn(matched)
			local r = {}
			local ri = 1
			while ri <= #repl do
				local rc = repl:sub(ri, ri)
				if rc == "&" then r[#r + 1] = matched
				elseif rc == "\\" then
					ri = ri + 1
					local nc = repl:sub(ri, ri)
					if nc == "&" then r[#r + 1] = "&"
					elseif nc == "\\" then r[#r + 1] = "\\"
					else r[#r + 1] = "\\" .. nc end
				else r[#r + 1] = rc end
				ri = ri + 1
			end
			return table.concat(r)
		end
		local new_s, count = self:regex_sub(s, pat, repl_fn, name == "gsub")
		if target_node then
			self:set_lvalue(target_node, new_s, locals)
		else
			self.record = new_s; self:split_record()
		end
		return count
	elseif name == "match" then
		local s = M.to_string(self, self:eval_expr(args[1], locals))
		local pat = self:get_pat(args[2], locals)
		local a, b = self:regex_find(s, pat)
		if a then
			self.rstart = a; self.rlength = b - a + 1
			return a
		else
			self.rstart = 0; self.rlength = -1
			return 0
		end
	elseif name == "sprintf" then
		local fmt = M.to_string(self, self:eval_expr(args[1], locals))
		local fargs = {}
		for i = 2, #args do fargs[i - 1] = self:eval_expr(args[i], locals) end
		return self:awk_sprintf(fmt, fargs)
	elseif name == "tolower" then
		return M.to_string(self, self:eval_expr(args[1], locals)):lower()
	elseif name == "toupper" then
		return M.to_string(self, self:eval_expr(args[1], locals)):upper()
	elseif name == "int" then
		local n = M.to_number(self:eval_expr(args[1], locals))
		return n >= 0 and math.floor(n) or math.ceil(n)
	elseif name == "sqrt" then return math.sqrt(M.to_number(self:eval_expr(args[1], locals)))
	elseif name == "exp" then return math.exp(M.to_number(self:eval_expr(args[1], locals)))
	elseif name == "log" then return math.log(M.to_number(self:eval_expr(args[1], locals)))
	elseif name == "sin" then return math.sin(M.to_number(self:eval_expr(args[1], locals)))
	elseif name == "cos" then return math.cos(M.to_number(self:eval_expr(args[1], locals)))
	elseif name == "atan2" then
		return math.atan(M.to_number(self:eval_expr(args[1], locals)), M.to_number(self:eval_expr(args[2], locals)))
	elseif name == "rand" then
		return math.random()
	elseif name == "srand" then
		local prev = self.rand_seed
		if #args > 0 then
			self.rand_seed = math.floor(M.to_number(self:eval_expr(args[1], locals)))
		else
			self.rand_seed = os.time()
		end
		math.randomseed(self.rand_seed)
		return prev
	elseif name == "system" then
		local cmd = M.to_string(self, self:eval_expr(args[1], locals))
		local ok, _, code = os.execute(cmd)
		return code or (ok and 0 or 1)
	elseif name == "close" then
		local target = M.to_string(self, self:eval_expr(args[1], locals))
		if self.output_files[target] then
			self.output_files[target]:close(); self.output_files[target] = nil; return 0
		elseif self.output_pipes[target] then
			self.output_pipes[target]:close(); self.output_pipes[target] = nil; return 0
		elseif self.input_pipes[target] then
			self.input_pipes[target]:close(); self.input_pipes[target] = nil; return 0
		end
		return -1
	else
		-- User-defined function
		return self:call_user_func(name, args, locals)
	end
end

-- Call a user-defined function
function M:call_user_func(name, arg_nodes, caller_locals)
	local func = self.functions[name]
	if not func then error("awk: undefined function " .. name) end
	local new_locals = {}
	-- Bind parameters
	for i, param in ipairs(func.params) do
		if i <= #arg_nodes then
			local arg_node = arg_nodes[i]
			-- Check if passing an array (NAME that is an array)
			if arg_node.type == "name" then
				local arr = self.globals[arg_node.name]
				if type(arr) == "table" then
					new_locals[param] = arr -- pass by reference
				else
					new_locals[param] = self:eval_expr(arg_node, caller_locals)
				end
			else
				new_locals[param] = self:eval_expr(arg_node, caller_locals)
			end
		else
			new_locals[param] = "" -- extra params are local vars
		end
	end
	local sig = self:exec_stmt(func.body, new_locals)
	if sig == RETURN then
		return self.return_value
	end
	return ""
end

-- Evaluate getline
function M:eval_getline(node, locals)
	-- For now, basic getline from stdin or file
	local line
	if node.source then
		local fname = M.to_string(self, self:eval_expr(node.source.expr, locals))
		if not self.input_files then self.input_files = {} end
		if not self.input_files[fname] then
			self.input_files[fname] = io.open(fname, "r")
		end
		if self.input_files[fname] then
			line = self.input_files[fname]:read("l")
		end
	elseif node.pipe_from then
		local cmd = M.to_string(self, node.pipe_from)
		if not self.input_pipes[cmd] then
			self.input_pipes[cmd] = io.popen(cmd, "r")
		end
		if self.input_pipes[cmd] then
			line = self.input_pipes[cmd]:read("l")
		end
	else
		-- getline from current input - read next record
		line = self:read_next_record()
	end
	if not line then return 0 end
	if node.var then
		self:set_lvalue(node.var, line, locals)
	else
		self.record = line
		self:split_record()
	end
	if not node.source and not node.pipe_from then
		self.nr = self.nr + 1
		self.fnr = self.fnr + 1
	end
	return 1
end

-- Placeholder for reading next record (set by the driver)
function M:read_next_record()
	return nil
end

-- Run a complete awk program against input records
function M:run(program, get_record)
	-- Register functions
	for _, rule in ipairs(program.rules) do
		if rule.type == "function" then
			self.functions[rule.name] = rule
		end
	end

	-- Execute BEGIN rules
	for _, rule in ipairs(program.rules) do
		if rule.type == "rule" and rule.pattern and rule.pattern.type == "BEGIN" then
			local sig = self:exec_stmt(rule.action, nil)
			if sig == EXIT then
				self:run_end(program)
				return self.exit_code or 0
			end
		end
	end

	-- Process records
	self.read_next_record = get_record
	local range_active = {}
	while true do
		local rec = get_record(self)
		if not rec then break end
		self.record = rec
		self:split_record()
		self.nr = self.nr + 1
		self.fnr = self.fnr + 1

		for ri, rule in ipairs(program.rules) do
			if rule.type == "rule" and rule.pattern then
				if rule.pattern.type == "BEGIN" or rule.pattern.type == "END" then
					-- skip
				elseif rule.pattern.type == "range" then
					if not range_active[ri] then
						if M.is_true(self:eval_expr(rule.pattern.from, nil)) then
							range_active[ri] = true
						end
					end
					if range_active[ri] then
						local sig = self:exec_stmt(rule.action or { type = "block", stmts = { { type = "print", args = {} } } }, nil)
						if sig == NEXT then break
						elseif sig == EXIT then self:run_end(program); return self.exit_code or 0 end
						if M.is_true(self:eval_expr(rule.pattern.to, nil)) then
							range_active[ri] = false
						end
					end
				else
					if M.is_true(self:eval_expr(rule.pattern, nil)) then
						local action = rule.action or { type = "block", stmts = { { type = "print", args = {} } } }
						local sig = self:exec_stmt(action, nil)
						if sig == NEXT then break
						elseif sig == EXIT then self:run_end(program); return self.exit_code or 0 end
					end
				end
			elseif rule.type == "rule" and not rule.pattern then
				local sig = self:exec_stmt(rule.action, nil)
				if sig == NEXT then break
				elseif sig == EXIT then self:run_end(program); return self.exit_code or 0 end
			end
		end
	end

	self:run_end(program)
	return self.exit_code or 0
end

-- Execute END rules and close files
function M:run_end(program)
	for _, rule in ipairs(program.rules) do
		if rule.type == "rule" and rule.pattern and rule.pattern.type == "END" then
			self:exec_stmt(rule.action, nil)
		end
	end
	for _, f in pairs(self.output_files) do f:close() end
	for _, f in pairs(self.output_pipes) do f:close() end
	if self.input_files then
		for _, f in pairs(self.input_files) do f:close() end
	end
	for _, f in pairs(self.input_pipes) do f:close() end
end

return M

