#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$D/.." && pwd)"
export LUA_PATH="$ROOT/?.lua;$LUA_PATH"
LN="lua5.4 $D/ln.lua"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 1
echo data > f

$LN f hard && [ -f hard ] || exit 1
$LN -s f soft && [ -L soft ] || exit 1
[ "$(readlink soft)" = "f" ] || exit 1
# -f replaces an existing link
$LN -sf hard soft && [ "$(readlink soft)" = "hard" ] || exit 1
# without -f it is an error
$LN -s f soft 2>/dev/null && exit 1
# several into a directory. A relative symlink made there points inside
# it, so what exists is the link and not what it names.
mkdir d && $LN -s f hard d || exit 1
[ -L d/f ] && [ -L d/hard ] || exit 1
$LN 2>/dev/null && exit 1
$LN -Z a b 2>/dev/null && exit 1
exit 0
