#!/bin/sh
# SPDX-License-Identifier: ISC
set -e
D="$(dirname "$0")"

# leading spaces to tab (default 8)
out=$(printf '        hello\n' | lua5.4 "$D/unexpand.lua")
expected=$(printf '\thello\n')
[ "$out" = "$expected" ] || { echo "FAIL: leading 8 spaces"; exit 1; }

# custom tabstop
out=$(printf '    hello\n' | lua5.4 "$D/unexpand.lua" -t 4)
expected=$(printf '\thello\n')
[ "$out" = "$expected" ] || { echo "FAIL: -t 4"; exit 1; }

# only leading by default
out=$(printf '        a        b\n' | lua5.4 "$D/unexpand.lua")
expected=$(printf '\ta        b\n')
[ "$out" = "$expected" ] || { echo "FAIL: leading only"; exit 1; }

echo "PASS"
