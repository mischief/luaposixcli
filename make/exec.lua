-- SPDX-License-Identifier: ISC
-- make/exec.lua - rule storage, inference rules, and signal handling for POSIX make
local unistd = require("posix.unistd")
local stat = require("posix.sys.stat")
local signal = require("posix.signal")

local M = {}

-- Create a new executor
function M.new(env, opts)
	local self = {
		env = env,
		opts = opts or {},
		rules = {}, -- target -> {prereqs={}, recipes={}, double_colon=false}
		inference = {}, -- list of {from_suffix, to_suffix, recipes}
		pattern_rules = {}, -- list of {target_pat, prereq_pat, recipes}
		suffixes = { ".o", ".c", ".y", ".l", ".a", ".sh" },
		phony = {}, -- target -> true
		precious = {}, -- target -> true
		default_target = nil,
		current_target = nil, -- for signal handler
	}
	return setmetatable(self, { __index = M })
end

-- Install signal handlers for cleanup
function M:install_signals()
	local self_ref = self
	local handler = function(signo)
		if self_ref.current_target then
			local t = self_ref.current_target
			if not self_ref.precious[t] and not self_ref.phony[t] then
				local s = stat.stat(t)
				if s then
					io.stderr:write("make: *** Deleting file '" .. t .. "'\n")
					os.remove(t)
				end
			end
		end
		signal.signal(signo, signal.SIG_DFL)
		signal.kill(unistd.getpid(), signo)
	end
	signal.signal(signal.SIGINT, handler)
	signal.signal(signal.SIGTERM, handler)
	signal.signal(signal.SIGHUP, handler)
end

-- Load parsed nodes into the executor
function M:load(nodes)
	for _, node in ipairs(nodes) do
		if node.type == "rule" then
			self:add_rule(node)
		end
	end
end

-- Add a rule node
function M:add_rule(node)
	local targets = node.targets
	local prereqs = node.prerequisites
	local recipes = node.recipes or {}

	-- Special targets
	if #targets == 1 then
		local t = targets[1]
		if t == ".PHONY" then
			for _, p in ipairs(prereqs) do
				local ep = self.env:expand(p)
				for w in ep:gmatch("%S+") do self.phony[w] = true end
			end
			return
		elseif t == ".SUFFIXES" then
			if #prereqs == 0 then
				self.suffixes = {}
			else
				for _, p in ipairs(prereqs) do
					local found = false
					for _, s in ipairs(self.suffixes) do
						if s == p then found = true; break end
					end
					if not found then self.suffixes[#self.suffixes + 1] = p end
				end
			end
			return
		elseif t == ".PRECIOUS" then
			if #prereqs == 0 then self.precious_all = true
			else for _, p in ipairs(prereqs) do
				local ep = self.env:expand(p)
				for w in ep:gmatch("%S+") do self.precious[w] = true end
			end end
			return
		elseif t == ".DEFAULT" then
			self.default_rule = { prereqs = {}, recipes = recipes }
			return
		elseif t == ".SILENT" then
			if #prereqs == 0 then self.opts.silent = true
			else for _, p in ipairs(prereqs) do
				self.rules[p] = self.rules[p] or { prereqs = {}, recipes = {} }
				self.rules[p].silent = true
			end end
			return
		elseif t == ".IGNORE" then
			if #prereqs == 0 then self.opts.ignore_errors = true
			else for _, p in ipairs(prereqs) do
				self.rules[p] = self.rules[p] or { prereqs = {}, recipes = {} }
				self.rules[p].ignore_errors = true
			end end
			return
		elseif t == ".POSIX" then
			return
		end
	end

	-- Inference rule: .s1.s2 or .s1 (single-suffix)
	if node.inference and #targets == 1 and #prereqs == 0 then
		local t = targets[1]
		for _, s2 in ipairs(self.suffixes) do
			if t:sub(-#s2) == s2 and #t > #s2 then
				local s1 = t:sub(1, #t - #s2)
				for _, sx in ipairs(self.suffixes) do
					if sx == s1 then
						self.inference[#self.inference + 1] = {
							from_suffix = s1, to_suffix = s2, recipes = recipes,
						}
						return
					end
				end
			end
		end
		for _, s in ipairs(self.suffixes) do
			if t == s then
				self.inference[#self.inference + 1] = {
					from_suffix = s, to_suffix = "", recipes = recipes,
					single_suffix = true,
				}
				return
			end
		end
	end

	-- Pattern rule: target contains %
	if #targets == 1 and targets[1]:find("%%") then
		local prereq_pat = prereqs[1] or ""
		self.pattern_rules[#self.pattern_rules + 1] = {
			target_pat = targets[1], prereq_pat = prereq_pat, recipes = recipes,
		}
		return
	end

	-- Normal rule
	for _, t in ipairs(targets) do
		local expanded_t = self.env:expand(t)
		local expanded_prereqs = {}
		for _, p in ipairs(prereqs) do
			local ep = self.env:expand(p)
			for w in ep:gmatch("%S+") do expanded_prereqs[#expanded_prereqs + 1] = w end
		end

		if not self.default_target and not expanded_t:match("^%.") then
			self.default_target = expanded_t
		end

		local existing = self.rules[expanded_t]
		if existing and not node.double_colon then
			for _, p in ipairs(expanded_prereqs) do
				existing.prereqs[#existing.prereqs + 1] = p
			end
			if #recipes > 0 then existing.recipes = recipes end
		else
			self.rules[expanded_t] = {
				prereqs = expanded_prereqs,
				recipes = recipes,
				double_colon = node.double_colon,
			}
		end
	end
end

-- Get modification time of a file (nil if doesn't exist)
local function mtime(path)
	local s = stat.stat(path)
	if not s then return nil end
	return s.st_mtime
end

-- Find a matching pattern rule for target
function M:find_pattern_rule(target)
	local eval = require("make.eval")
	for _, pr in ipairs(self.pattern_rules) do
		local stem = eval.pattern_stem(pr.target_pat, target)
		if stem then
			local prereq = pr.prereq_pat:gsub("%%", stem)
			if prereq == "" or mtime(prereq) or self.rules[prereq] then
				return {
					prereqs = prereq ~= "" and { prereq } or {},
					recipes = pr.recipes,
					stem = stem,
				}
			end
		end
	end
	return nil
end

-- Find a matching inference rule for target (follows .SUFFIXES order)
function M:find_inference_rule(target)
	for _, to_suf in ipairs(self.suffixes) do
		if to_suf ~= "" and #target > #to_suf and target:sub(-#to_suf) == to_suf then
			local stem = target:sub(1, #target - #to_suf)
			for _, from_suf in ipairs(self.suffixes) do
				for _, ir in ipairs(self.inference) do
					if ir.to_suffix == to_suf and ir.from_suffix == from_suf then
						local prereq = stem .. from_suf
						if mtime(prereq) or self.rules[prereq] then
							return {
								prereqs = { prereq },
								recipes = ir.recipes,
								stem = stem,
							}
						end
					end
				end
			end
		end
	end

	for _, ir in ipairs(self.inference) do
		if ir.single_suffix then
			local prereq = target .. ir.from_suffix
			if mtime(prereq) or self.rules[prereq] then
				return {
					prereqs = { prereq },
					recipes = ir.recipes,
					stem = target,
				}
			end
		end
	end

	return nil
end

-- Add default POSIX inference rules
function M:add_default_rules()
	self.inference[#self.inference + 1] = {
		from_suffix = ".c", to_suffix = ".o",
		recipes = { "$(CC) $(CFLAGS) -c $<" },
	}
	self.inference[#self.inference + 1] = {
		from_suffix = ".c", to_suffix = "",
		recipes = { "$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<" },
		single_suffix = true,
	}
	self.inference[#self.inference + 1] = {
		from_suffix = ".sh", to_suffix = "",
		recipes = { "cp $< $@", "chmod a+x $@" },
		single_suffix = true,
	}
	self.inference[#self.inference + 1] = {
		from_suffix = ".y", to_suffix = ".o",
		recipes = { "$(YACC) $(YFLAGS) $<", "$(CC) $(CFLAGS) -c y.tab.c", "rm -f y.tab.c", "mv y.tab.o $@" },
	}
	self.inference[#self.inference + 1] = {
		from_suffix = ".y", to_suffix = ".c",
		recipes = { "$(YACC) $(YFLAGS) $<", "mv y.tab.c $@" },
	}
	self.inference[#self.inference + 1] = {
		from_suffix = ".l", to_suffix = ".o",
		recipes = { "$(LEX) $(LFLAGS) $<", "$(CC) $(CFLAGS) -c lex.yy.c", "rm -f lex.yy.c", "mv lex.yy.o $@" },
	}
	self.inference[#self.inference + 1] = {
		from_suffix = ".l", to_suffix = ".c",
		recipes = { "$(LEX) $(LFLAGS) $<", "mv lex.yy.c $@" },
	}
	self.inference[#self.inference + 1] = {
		from_suffix = ".c", to_suffix = ".a",
		recipes = { "$(CC) $(CFLAGS) -c $<", "$(AR) $(ARFLAGS) $@ $*.o", "rm -f $*.o" },
	}
end

return M
