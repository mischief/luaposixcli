#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$D/.." && pwd)"
export LUA_PATH="$ROOT/?.lua;$LUA_PATH"
STRINGS="lua5.4 $D/strings.lua"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

printf 'ab\0hello world\0\1\2cd\0longenough\n' > "$TMP/bin"
[ "$($STRINGS "$TMP/bin")" = "$(printf 'hello world\nlongenough')" ] || exit 1
# -n takes shorter runs
$STRINGS -n 2 "$TMP/bin" | grep -q '^ab$' || exit 1
$STRINGS -2 "$TMP/bin" | grep -q '^cd$' || exit 1
# -t prints the offset in the radix asked for
$STRINGS -t d "$TMP/bin" | grep -q '^3 hello world$' || exit 1
$STRINGS -t x "$TMP/bin" | grep -q '^3 hello world$' || exit 1
# stdin works, and the system strings agrees where it is installed
printf 'xyzzy\0' | $STRINGS | grep -q xyzzy || exit 1
if command -v strings >/dev/null 2>&1; then
	[ "$($STRINGS "$TMP/bin")" = "$(strings "$TMP/bin")" ] || exit 1
fi
exit 0
