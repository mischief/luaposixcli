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
[ "$(printf 'a\nb' | $TAIL -n1)" = "b" ] || exit 1

# -f keeps reading after the end of the file. The writer is backgrounded
# on its own, since a & at the end of an && chain backgrounds the chain.
TMPF=$(mktemp)
trap 'rm -f "$TMPF"' EXIT
seq 3 > "$TMPF"
{ sleep 0.3; echo four >> "$TMPF"; sleep 0.3; echo five >> "$TMPF"; } &
[ "$(timeout 2 $TAIL -f -n 1 "$TMPF" | tr '\n' ' ')" = "3 four five " ] || exit 1
wait
exit 0
