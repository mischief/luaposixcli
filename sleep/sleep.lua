#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
unistd.sleep(math.floor(tonumber(arg[1]) or 0))
