#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
local out = table.concat(arg, " ") .. "\n"
unistd.write(1, out)
