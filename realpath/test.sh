#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$D/.." && pwd)"
export LUA_PATH="$ROOT/?.lua;$LUA_PATH"
REALPATH="lua5.4 $D/realpath.lua"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/dir"; : > "$TMP/dir/f"; ln -s dir "$TMP/link"; ln -s f "$TMP/dir/inner"

cd "$TMP" || exit 1
[ "$($REALPATH dir/f)" = "$(realpath dir/f)" ] &&
[ "$($REALPATH link/f)" = "$(realpath link/f)" ] &&
[ "$($REALPATH dir/inner)" = "$(realpath dir/inner)" ] &&
[ "$($REALPATH ./dir/../dir/f)" = "$(realpath ./dir/../dir/f)" ] &&
# a name that does not exist yet is fine, under a directory that does
[ "$($REALPATH nothere)" = "$(realpath nothere)" ] &&
! $REALPATH -e nothere 2>/dev/null &&
! $REALPATH nodir/nothere 2>/dev/null &&
! $REALPATH 2>/dev/null &&
! $REALPATH -Z x 2>/dev/null
