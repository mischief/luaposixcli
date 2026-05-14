#!/bin/sh
# SPDX-License-Identifier: ISC
# not a tty in test context — should exit 1
lua5.4 "$(dirname "$0")/tty.lua" </dev/null
[ $? -eq 1 ]
