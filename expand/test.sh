#!/bin/sh
# SPDX-License-Identifier: ISC
set -e
D="$(dirname "$0")"

# default tabstop 8
out=$(printf 'a\tb' | lua5.4 "$D/expand.lua")
[ "$out" = "a       b" ] || { echo "FAIL: default"; exit 1; }

# custom tabstop
out=$(printf 'a\tb' | lua5.4 "$D/expand.lua" -t 4)
[ "$out" = "a   b" ] || { echo "FAIL: -t 4"; exit 1; }

# tab at column boundary
out=$(printf '\tx' | lua5.4 "$D/expand.lua" -t 4)
[ "$out" = "    x" ] || { echo "FAIL: tab at start"; exit 1; }

echo "PASS"
