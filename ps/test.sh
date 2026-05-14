#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
# -A should list init (pid 1)
lua5.4 "$D/ps.lua" -A | grep -q "^ *1 " &&
# -f should show UID header
lua5.4 "$D/ps.lua" -Af | grep -q "^UID"
