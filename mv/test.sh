#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
TMP=$(mktemp)
echo "data" > "$TMP"
DST="${TMP}_moved"
lua5.4 "$D/mv.lua" "$TMP" "$DST"
[ ! -f "$TMP" ] && [ "$(cat "$DST")" = "data" ]
RET=$?
rm -f "$DST"
exit $RET
