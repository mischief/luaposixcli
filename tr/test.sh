#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
[ "$(printf 'hello' | lua5.4 "$D/tr.lua" a-z A-Z)" = "HELLO" ] &&
[ "$(printf 'hello' | lua5.4 "$D/tr.lua" -d l)" = "heo" ] &&
[ "$(printf 'aabbc' | lua5.4 "$D/tr.lua" -s a-z)" = "abc" ] &&
# -c is everything the set leaves out
[ "$(printf 'abc123' | lua5.4 "$D/tr.lua" -c '0-9' .)" = "...123" ] &&
[ "$(printf 'abc123' | lua5.4 "$D/tr.lua" -cd '0-9')" = "123" ] &&
! lua5.4 "$D/tr.lua" -Z a </dev/null 2>/dev/null
