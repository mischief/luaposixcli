#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
[ "$(printf 'b\na\nc\n' | lua5.4 "$D/sort.lua")" = "$(printf 'a\nb\nc')" ] &&
[ "$(printf '10\n2\n1\n' | lua5.4 "$D/sort.lua" -n)" = "$(printf '1\n2\n10')" ] &&
[ "$(printf 'a\nb\nc\n' | lua5.4 "$D/sort.lua" -r)" = "$(printf 'c\nb\na')" ] &&
[ "$(printf 'b 2\na 3\nc 1\n' | lua5.4 "$D/sort.lua" -k 2 -n)" = "$(printf 'c 1\nb 2\na 3')" ]
