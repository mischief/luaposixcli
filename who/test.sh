#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$D/.." && pwd)"
export LUA_PATH="$ROOT/?.lua;$LUA_PATH"
WHO="lua5.4 $D/who.lua"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# bad options and too many operands are refused
$WHO -Z 2>/dev/null && exit 1
$WHO one two three 2>/dev/null && exit 1
# "who am i" says nothing off a terminal, and says it quietly
$WHO am i >/dev/null || exit 1

# a file of login records of our own, which is the POSIX file operand
lua5.4 -e '
local utmp = require("luaposixcli.utmp")
local f = assert(io.open("'"$TMP"'/utmp", "wb"))
f:write(utmp.pack({ type = utmp.BOOT_TIME, time = 1000000000 }))
f:write(utmp.pack({ type = utmp.USER_PROCESS, pid = 42, line = "tty1",
	user = "alice", host = "", time = 1600000000 }))
f:write(utmp.pack({ type = utmp.USER_PROCESS, pid = 43, line = "pts/0",
	user = "bob", host = "elsewhere", time = 1600000060 }))
f:write(utmp.pack({ type = utmp.DEAD_PROCESS, pid = 44, line = "pts/1",
	user = "carol", time = 1600000120 }))
f:close()' || exit 1

[ "$($WHO "$TMP/utmp" | wc -l)" = "2" ] || exit 1
$WHO "$TMP/utmp" | grep -q "^alice    tty1 " || exit 1
$WHO "$TMP/utmp" | grep -q "(elsewhere)$" || exit 1
# -d is the sessions that ended, -b the boot
$WHO -d "$TMP/utmp" | grep -q "^carol" || exit 1
$WHO -b "$TMP/utmp" | grep -q "system boot" || exit 1
# -q counts them
[ "$($WHO -q "$TMP/utmp" | tail -1)" = "# users=2" ] || exit 1
# -H puts a header above the same two lines
[ "$($WHO -H "$TMP/utmp" | wc -l)" = "3" ] || exit 1

# and what the system who says about the same records
if command -v who >/dev/null 2>&1; then
	[ "$($WHO "$TMP/utmp")" = "$(who "$TMP/utmp")" ] || exit 1
	[ "$($WHO -q "$TMP/utmp")" = "$(who -q "$TMP/utmp")" ] || exit 1
fi
exit 0
