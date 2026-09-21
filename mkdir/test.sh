#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$D/.." && pwd)"
export LUA_PATH="$ROOT/?.lua;$LUA_PATH"
MKDIR="lua5.4 $D/mkdir.lua"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 1

$MKDIR plain && [ -d plain ] || exit 1
# -p makes every level, and says nothing about one that is already there
$MKDIR -p a/b/c && [ -d a/b/c ] || exit 1
$MKDIR -p a/b/c || exit 1
# without -p a missing parent is an error
$MKDIR x/y 2>/dev/null && exit 1
# -m sets the mode of the directory made, umask and all
$MKDIR -m 700 secret && [ "$(stat -c%a secret)" = "700" ] || exit 1
$MKDIR -p -m 750 deep/er && [ "$(stat -c%a deep/er)" = "750" ] || exit 1
# a symbolic mode works too
$MKDIR -m u=rwx,go= sym && [ "$(stat -c%a sym)" = "700" ] || exit 1
# an existing directory without -p is an error, and -p is not a file name
$MKDIR plain 2>/dev/null && exit 1
[ -d ./-p ] && exit 1
# usage
$MKDIR 2>/dev/null && exit 1
$MKDIR -Z q 2>/dev/null && exit 1
exit 0
