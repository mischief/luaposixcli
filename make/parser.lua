-- SPDX-License-Identifier: ISC
-- make/parser.lua - POSIX Makefile parser

local M = {}

-- Strip inline comment (# not inside $(...) or ${...})
local function strip_comment(s)
	local depth = 0
	local i = 1
	while i <= #s do
		local c = s:sub(i, i)
		if c == "$" and i < #s then
			local nxt = s:sub(i + 1, i + 1)
			if nxt == "(" or nxt == "{" then depth = depth + 1; i = i + 2 end
		elseif (c == "(" or c == "{") and depth > 0 then
			depth = depth + 1
		elseif (c == ")" or c == "}") and depth > 0 then
			depth = depth - 1
		elseif c == "#" and depth == 0 then
			return s:sub(1, i - 1)
		end
		i = i + 1
	end
	return s
end

-- Parse a single line and classify it
local function parse_line(line, lineno)
	-- Recipe line (starts with tab)
	if line:sub(1, 1) == "\t" then
		return { type = "recipe", text = line:sub(2), lineno = lineno }
	end

	-- Strip comments
	local stripped = strip_comment(line)
	stripped = stripped:gsub("%s+$", "")
	if stripped == "" then return nil end

	-- Directives: include, -include, sinclude
	local inc_kw, inc_arg = stripped:match("^(%-?include)%s+(.+)")
	if not inc_kw then inc_kw, inc_arg = stripped:match("^(sinclude)%s+(.+)") end
	if inc_kw then
		return { type = "include", keyword = inc_kw, arg = inc_arg, lineno = lineno }
	end

	-- Conditionals
	local cond_kw = stripped:match("^(ifdef)%s") or stripped:match("^(ifndef)%s")
		or stripped:match("^(ifeq)[%s%(]") or stripped:match("^(ifneq)[%s%(]")
	if cond_kw then
		local arg = stripped:sub(#cond_kw + 1):match("^%s*(.*)")
		return { type = "conditional", keyword = cond_kw, arg = arg, lineno = lineno }
	end
	if stripped == "else" or stripped:match("^else%s") then
		return { type = "else", lineno = lineno }
	end
	if stripped == "endif" then
		return { type = "endif", lineno = lineno }
	end

	-- Export/unexport
	local export_arg = stripped:match("^export%s+(.*)")
	if export_arg then
		local name, op, val = export_arg:match("^([%w_%.%-/]+)%s*(:?:?[?+!]?=)%s*(.*)")
		if name then
			return { type = "assign", name = name, op = op, value = val, export = true, lineno = lineno }
		end
		return { type = "export", names = export_arg, lineno = lineno }
	end
	if stripped:match("^unexport%s") then
		return { type = "unexport", names = stripped:match("^unexport%s+(.*)"), lineno = lineno }
	end

	-- Variable assignment
	local name, op, val = stripped:match("^([%w_%.%-/]+)%s*(:?:?:?[?+!]?=)%s*(.*)")
	if name then
		return { type = "assign", name = name, op = op, value = val, lineno = lineno }
	end

	-- Rule line: targets : prerequisites [; recipe]
	local targets_str, sep, rest = stripped:match("^(.-)%s*(::?)%s*(.*)")
	if targets_str and targets_str ~= "" then
		local targets = {}
		for t in targets_str:gmatch("%S+") do targets[#targets + 1] = t end

		local prereqs_str, inline_recipe = rest:match("^(.-)%s*;%s*(.*)")
		if not prereqs_str then prereqs_str = rest end

		local prereqs = {}
		for p in prereqs_str:gmatch("%S+") do prereqs[#prereqs + 1] = p end

		-- Detect inference rules
		local is_inference = false
		if #targets == 1 and #prereqs == 0 then
			local t = targets[1]
			if t:match("^%.[%w]+%.[%w]+$") or (t:match("^%.[%w]+$") and t ~= ".PHONY"
				and t ~= ".SUFFIXES" and t ~= ".DEFAULT" and t ~= ".PRECIOUS"
				and t ~= ".SILENT" and t ~= ".IGNORE" and t ~= ".POSIX") then
				is_inference = true
			end
		end

		return {
			type = "rule",
			targets = targets,
			prerequisites = prereqs,
			double_colon = (sep == "::"),
			inference = is_inference,
			inline_recipe = inline_recipe,
			lineno = lineno,
		}
	end

	return nil
end

--- Parse Makefile source into a list of directives.
--- @param source string Makefile source text
--- @return table list of parsed nodes
function M.parse(source)
	-- Normalize line endings
	source = source:gsub("\r\n", "\n"):gsub("\r", "\n")
	if source:sub(-1) ~= "\n" then source = source .. "\n" end

	local nodes = {}
	local current_rule = nil
	local lineno = 0

	-- Split into raw lines, then handle continuations context-sensitively
	local lines = {}
	for line in source:gmatch("([^\n]*)\n") do
		lines[#lines + 1] = line
	end

	local i = 1
	while i <= #lines do
		lineno = lineno + 1
		local line = lines[i]

		if line:sub(1, 1) == "\t" then
			-- Recipe line: preserve backslash-newline (pass to shell as-is)
			-- Join continuation lines but keep the \n for the shell
			local parts = { line }
			while line:sub(-1) == "\\" and i < #lines do
				i = i + 1
				local next_line = lines[i]
				-- Strip leading tab on continuation
				if next_line:sub(1, 1) == "\t" then next_line = next_line:sub(2) end
				parts[#parts + 1] = next_line
			end
			local full = table.concat(parts, "\n")
			local node = parse_line(full, lineno)
			if node and node.type == "recipe" then
				if current_rule then
					current_rule.recipes[#current_rule.recipes + 1] = node.text
				end
			end
		else
			-- Non-recipe line: collapse backslash-newline to space
			while line:sub(-1) == "\\" and i < #lines do
				i = i + 1
				line = line:sub(1, -2) .. " " .. lines[i]:match("^%s*(.*)")
			end

			local node = parse_line(line, lineno)
			if node then
				if current_rule and current_rule.inline_recipe and current_rule.inline_recipe ~= "" then
					current_rule.recipes[#current_rule.recipes + 1] = current_rule.inline_recipe
					current_rule.inline_recipe = nil
				end

				if node.type == "rule" then
					node.recipes = {}
					current_rule = node
				else
					current_rule = nil
				end
				nodes[#nodes + 1] = node
			end
		end
		i = i + 1
	end

	if current_rule and current_rule.inline_recipe and current_rule.inline_recipe ~= "" then
		current_rule.recipes[#current_rule.recipes + 1] = current_rule.inline_recipe
		current_rule.inline_recipe = nil
	end

	return nodes
end

return M
