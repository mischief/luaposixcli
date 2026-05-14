#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
# just verify it runs without error
lua5.4 "$D/logger.lua" -t luatest "test message from lua-os-utils"
