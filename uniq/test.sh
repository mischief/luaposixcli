#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
[ "$(printf 'a\na\nb\nc\nc\n' | lua5.4 "$D/uniq.lua")" = "$(printf 'a\nb\nc')" ] &&
[ "$(printf 'a\na\nb\n' | lua5.4 "$D/uniq.lua" -c)" = "$(printf '      2 a\n      1 b')" ] &&
[ "$(printf 'a\na\nb\n' | lua5.4 "$D/uniq.lua" -d)" = "a" ]
