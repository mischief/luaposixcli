#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
TAIL="lua5.4 $D/tail.lua"
[ "$(seq 10 | $TAIL -3)" = "$(seq 8 10)" ] &&
[ "$(seq 10 | $TAIL -n 3)" = "$(seq 8 10)" ] &&
[ "$(seq 10 | $TAIL -n3)" = "$(seq 8 10)" ] &&
[ "$(seq 10 | $TAIL)" = "$(seq 10)" ] &&
# +N counts from the start
[ "$(seq 10 | $TAIL -n +9)" = "$(seq 9 10)" ] &&
# -c counts bytes
[ "$(printf 'abcdef' | $TAIL -c 2)" = "ef" ] &&
# a last line without a newline still comes out whole
[ "$(printf 'a\nb' | $TAIL -n1)" = "b" ]
