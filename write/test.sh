#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$D/.." && pwd)"
export LUA_PATH="$ROOT/?.lua;$LUA_PATH"
WRITE="lua5.4 $D/write.lua"

$WRITE 2>/dev/null && exit 1
$WRITE a b c 2>/dev/null && exit 1
# somebody who is not logged in is told about, not written to
$WRITE no_such_user_at_all </dev/null 2>&1 | grep -q "not logged in" || exit 1
$WRITE no_such_user_at_all pts/999 </dev/null 2>&1 | grep -q "not logged in on" || exit 1
exit 0
