#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$D/.." && pwd)"
export LUA_PATH="$ROOT/?.lua;$LUA_PATH"
MESG="lua5.4 $D/mesg.lua"

# off a terminal there is nothing to answer about
$MESG < /dev/null 2>/dev/null && exit 1
$MESG -Z 2>/dev/null && exit 1
$MESG y n 2>/dev/null && exit 1
$MESG maybe 2>/dev/null && exit 1

# on a terminal of our own, y and n set the bit and say which it is
command -v script >/dev/null 2>&1 || exit 0
OUT=$(script -qec "$MESG y; $MESG; $MESG n; $MESG" /dev/null | tr -d '\r')
[ "$OUT" = "$(printf 'is y\nis n')" ] || exit 1
exit 0
