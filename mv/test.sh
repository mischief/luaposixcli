#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$D/.." && pwd)"
export LUA_PATH="$ROOT/?.lua;$LUA_PATH"
MV="lua5.4 $D/mv.lua"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 1
echo data > f

$MV f g && [ ! -f f ] && [ "$(cat g)" = "data" ] || exit 1
# into a directory, keeping the name
mkdir d && $MV g d || exit 1
[ -f d/g ] || exit 1
# several at once need a directory
echo x > a && echo y > b && $MV a b d || exit 1
[ -f d/a ] && [ -f d/b ] || exit 1
echo x > a && echo y > b && $MV a b notadir 2>/dev/null && exit 1
# -f replaces what is there
echo new > n && $MV -f n d/g || exit 1
[ "$(cat d/g)" = "new" ] || exit 1
$MV 2>/dev/null && exit 1
$MV nosuch there 2>/dev/null && exit 1
exit 0
