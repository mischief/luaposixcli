#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$D/.." && pwd)"
export LUA_PATH="$ROOT/?.lua;$LUA_PATH"
SPLIT="lua5.4 $D/split.lua"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
seq 25 > "$TMP/n"
mkdir "$TMP/ours" "$TMP/sys"

(cd "$TMP/ours" && $SPLIT -l 10 "$TMP/n") && (cd "$TMP/sys" && split -l 10 "$TMP/n") &&
diff -r "$TMP/ours" "$TMP/sys" >/dev/null &&
rm -f "$TMP"/ours/* "$TMP"/sys/* &&
(cd "$TMP/ours" && $SPLIT -b 30 "$TMP/n" p) && (cd "$TMP/sys" && split -b 30 "$TMP/n" p) &&
diff -r "$TMP/ours" "$TMP/sys" >/dev/null &&
rm -f "$TMP"/ours/* "$TMP"/sys/* &&
(cd "$TMP/ours" && $SPLIT -a 3 -l 5 "$TMP/n") && (cd "$TMP/sys" && split -a 3 -l 5 "$TMP/n") &&
diff -r "$TMP/ours" "$TMP/sys" >/dev/null &&
! $SPLIT -Z 2>/dev/null
