#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
[ "$(lua5.4 "$D/expr.lua" 2 + 3)" = "5" ] &&
[ "$(lua5.4 "$D/expr.lua" 10 / 3)" = "3" ] &&
[ "$(lua5.4 "$D/expr.lua" 5 \* 4)" = "20" ] &&
[ "$(lua5.4 "$D/expr.lua" 10 % 3)" = "1" ] &&
[ "$(lua5.4 "$D/expr.lua" 3 \> 2)" = "1" ]
