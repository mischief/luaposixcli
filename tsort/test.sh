#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$D/.." && pwd)"
export LUA_PATH="$ROOT/?.lua;$LUA_PATH"
TSORT="lua5.4 $D/tsort.lua"
TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT
printf 'a b\nb c\nd e\nc d\n' > "$TMP"

[ "$($TSORT "$TMP")" = "$(tsort "$TMP")" ] &&
# a loop is reported and the order still comes out
[ "$(printf 'a b\nb a\n' | $TSORT 2>/dev/null | wc -l)" = "2" ] &&
printf 'a b\nb a\n' | $TSORT 2>&1 >/dev/null | grep -q loop &&
# an odd number of names is an error
! printf 'a b c\n' | $TSORT 2>/dev/null &&
! $TSORT -Z 2>/dev/null
