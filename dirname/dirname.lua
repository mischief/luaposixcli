#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local path = (arg[1] or ""):gsub("/+$", "")
print(path:match("^(.*)/[^/]+$") or ".")
