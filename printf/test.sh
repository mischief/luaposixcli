#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
[ "$(lua5.4 "$D/printf.lua" "hello %s\n" world)" = "hello world" ] &&
[ "$(lua5.4 "$D/printf.lua" "%d\n" 42)" = "42" ] &&
[ "$(lua5.4 "$D/printf.lua" "%05d\n" 7)" = "00007" ]
