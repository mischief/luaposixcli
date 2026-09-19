#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
PRINTF="lua5.4 $D/printf.lua"
[ "$($PRINTF "hello %s\n" world)" = "hello world" ] &&
[ "$($PRINTF "%d\n" 42)" = "42" ] &&
[ "$($PRINTF "%05d\n" 7)" = "00007" ] &&
# the format is reused until the operands run out
[ "$($PRINTF "%s\n" alpha beta gamma)" = "$(printf 'alpha\nbeta\ngamma')" ] &&
[ "$($PRINTF "%s-%s " a b c d)" = "a-b c-d " ] &&
[ "$($PRINTF "[%s]" )" = "[]" ] &&
[ "$($PRINTF "%b\n" 'a\tb')" = "$(printf 'a\tb')" ]
