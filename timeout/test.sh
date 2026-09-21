#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$D/.." && pwd)"
export LUA_PATH="$ROOT/?.lua;$LUA_PATH"
TIMEOUT="lua5.4 $D/timeout.lua"

# a command that finishes keeps its own status
[ "$($TIMEOUT 5 echo hi)" = "hi" ] &&
$TIMEOUT 5 true &&
! $TIMEOUT 5 false &&
$TIMEOUT 5 sh -c 'exit 3'; [ "$?" = "3" ] &&
# one that does not is ended, and says 124
$TIMEOUT 1 sleep 10; [ "$?" = "124" ] &&
# a utility that is not there is 127, as for any shell
$TIMEOUT 5 no-such-utility >/dev/null 2>&1; [ "$?" = "127" ] &&
! $TIMEOUT 2>/dev/null &&
! $TIMEOUT -Z 1 true 2>/dev/null
