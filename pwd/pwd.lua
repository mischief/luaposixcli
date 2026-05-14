#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: ISC
local unistd = require("posix.unistd")
unistd.write(1, unistd.getcwd() .. "\n")
