#!/bin/sh
# SPDX-License-Identifier: ISC
set -e
D="$(dirname "$0")"

# basic fold at 10
out=$(printf 'abcdefghijklmnop' | lua5.4 "$D/fold.lua" -w 10)
expected=$(printf 'abcdefghij\nklmnop')
[ "$out" = "$expected" ] || { echo "FAIL: basic fold"; exit 1; }

# fold with -s (break at spaces)
out=$(printf 'hello world foo bar' | lua5.4 "$D/fold.lua" -w 10 -s)
expected=$(printf 'hello \nworld foo \nbar')
[ "$out" = "$expected" ] || { echo "FAIL: -s"; exit 1; }

# default width 80
out=$(printf '%0100d' 0 | lua5.4 "$D/fold.lua")
first=$(printf '%s\n' "$out" | head -1)
[ "${#first}" = "80" ] || { echo "FAIL: default width (got ${#first})"; exit 1; }

echo "PASS"
