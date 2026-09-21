#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$D/.." && pwd)"
export LUA_PATH="$ROOT/?.lua;$LUA_PATH"
CP="lua5.4 $D/cp.lua"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 1
mkdir -p tree/sub && echo one > tree/a && echo two > tree/sub/b && ln -s a tree/link

$CP tree/a plain && [ "$(cat plain)" = "one" ] || exit 1
# -R copies the whole tree, symlinks as symlinks
$CP -R tree copy && diff -r tree copy >/dev/null || exit 1
[ -L copy/link ] || exit 1
# a directory without -R is refused
$CP tree nope 2>/dev/null && exit 1
# several into a directory
mkdir into && $CP tree/a tree/sub/b into || exit 1
[ -f into/a ] && [ -f into/b ] || exit 1
# -p keeps the mode
chmod 700 tree/a && $CP -p tree/a kept || exit 1
[ "$(stat -c%a kept)" = "700" ] || exit 1
# usage and a missing source
$CP 2>/dev/null && exit 1
$CP -Z a b 2>/dev/null && exit 1
$CP nosuch there 2>/dev/null && exit 1
exit 0
