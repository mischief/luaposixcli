#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
[ "$(printf 'a:b:c\n' | lua5.4 "$D/cut.lua" -d: -f2)" = "b" ] &&
[ "$(printf 'hello\n' | lua5.4 "$D/cut.lua" -c1-3)" = "hel" ] &&
[ "$(printf 'a:b:c\n' | lua5.4 "$D/cut.lua" -d: -f1,3)" = "a:c" ]
