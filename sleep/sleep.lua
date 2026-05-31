#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local signal = require("posix.signal")
local unistd = require("posix.unistd")
signal.signal(signal.SIGINT, function() os.exit(130) end)
unistd.sleep(math.floor(tonumber(arg[1]) or 0))
