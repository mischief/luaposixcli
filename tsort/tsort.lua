#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
-- tsort - order a list of pairs so that every left comes before its right
local prefix = ((arg[0] or "tsort"):match("(.+/)") or "./") .. "../"
package.path = prefix .. "?.lua;" .. prefix .. "share/lua/5.4/?.lua;" .. package.path

local unistd = require("posix.unistd")
local util = require("luaposixcli.util")

local files = {}
for _, a in ipairs(arg) do
	if a == "--" then
	elseif a:sub(1, 1) == "-" and #a > 1 then
		util.die("usage: tsort [file]", 2)
	else
		files[#files + 1] = a
	end
end
if #files > 1 then util.die("usage: tsort [file]", 2) end

local text, err = util.slurp(files[1])
if not text then util.die(err or (files[1] .. ": cannot read")) end

-- the graph, and the order the names were first seen, so that a tie is
-- broken the same way every run
local after, before_count, seen, order = {}, {}, {}, {}

local function note(name)
	if not seen[name] then
		seen[name] = true
		order[#order + 1] = name
		after[name] = {}
		before_count[name] = 0
	end
end

local words = {}
for word in text:gmatch("%S+") do words[#words + 1] = word end
if #words % 2 ~= 0 then
	util.die("odd number of tokens")
end

for i = 1, #words, 2 do
	local a, b = words[i], words[i + 1]
	note(a)
	note(b)
	if a ~= b then
		-- an edge counted twice would hold b back twice
		local already = false
		for _, to in ipairs(after[a]) do
			if to == b then already = true break end
		end
		if not already then
			after[a][#after[a] + 1] = b
			before_count[b] = before_count[b] + 1
		end
	end
end

local ready = {}
for _, name in ipairs(order) do
	if before_count[name] == 0 then ready[#ready + 1] = name end
end

local done, printed, status = 0, {}, 0

-- A loop has no first element, so nothing is ready and the ordering
-- stalls. Say so, break it at the node closest to being ready, and
-- carry on: a partial order is more use than none.
local function break_loop()
	local pick, fewest = nil, math.huge
	for _, name in ipairs(order) do
		if not printed[name] and before_count[name] < fewest then
			pick, fewest = name, before_count[name]
		end
	end
	if pick then
		unistd.write(2, "tsort: input contains a loop\n")
		status = 1
		before_count[pick] = 0
		ready[#ready + 1] = pick
	end
end

while done < #order do
	if #ready == 0 then
		break_loop()
		if #ready == 0 then break end
	end
	local name = table.remove(ready, 1)
	if not printed[name] then
		printed[name] = true
		unistd.write(1, name .. "\n")
		done = done + 1
		for _, to in ipairs(after[name]) do
			before_count[to] = before_count[to] - 1
			if before_count[to] == 0 and not printed[to] then
				ready[#ready + 1] = to
			end
		end
	end
end

os.exit(status)
