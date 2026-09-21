#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$D/.." && pwd)"
export LUA_PATH="$ROOT/?.lua;$LUA_PATH"
RMDIR="lua5.4 $D/rmdir.lua"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 1

mkdir one && $RMDIR one && [ ! -d one ] || exit 1
# -p takes the parents too, stopping where one will not go
mkdir -p a/b/c && $RMDIR -p a/b/c && [ ! -d a ] || exit 1
mkdir -p k/l && touch k/keep && $RMDIR -p k/l && [ -d k ] || exit 1
# a directory with something in it stays
mkdir full && touch full/x && $RMDIR full 2>/dev/null && exit 1
[ -d full ] || exit 1
$RMDIR 2>/dev/null && exit 1
$RMDIR -Z q 2>/dev/null && exit 1
exit 0
