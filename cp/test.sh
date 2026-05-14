#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
TMP=$(mktemp)
echo "hello" > "$TMP"
DST="${TMP}_copy"
lua5.4 "$D/cp.lua" "$TMP" "$DST"
[ "$(cat "$DST")" = "hello" ]
RET=$?
rm -f "$TMP" "$DST"
exit $RET
