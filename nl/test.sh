#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$D/.." && pwd)"
export LUA_PATH="$ROOT/?.lua;$LUA_PATH"
NL="lua5.4 $D/nl.lua"
TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT
printf 'one\n\ntwo\nthree\n' > "$TMP"

# an empty line is not numbered unless -b a says so
[ "$($NL "$TMP")" = "$(nl "$TMP")" ] &&
[ "$($NL -b a "$TMP")" = "$(nl -b a "$TMP")" ] &&
[ "$($NL -b n "$TMP")" = "$(nl -b n "$TMP")" ] &&
[ "$($NL -v 10 -i 5 "$TMP")" = "$(nl -v 10 -i 5 "$TMP")" ] &&
[ "$($NL -w 3 -s : "$TMP")" = "$(nl -w 3 -s : "$TMP")" ] &&
! $NL -Z 2>/dev/null
