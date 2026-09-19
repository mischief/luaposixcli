#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
HEAD="lua5.4 $D/head.lua"
[ "$(seq 10 | $HEAD -3)" = "$(seq 3)" ] &&
[ "$(seq 10 | $HEAD -n 3)" = "$(seq 3)" ] &&
[ "$(seq 10 | $HEAD -n3)" = "$(seq 3)" ] &&
[ "$(seq 10 | $HEAD)" = "$(seq 10)" ] &&
[ "$(printf 'abcdef' | $HEAD -c 3)" = "abc" ]
