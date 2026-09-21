#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$D/.." && pwd)"
export LUA_PATH="$ROOT/?.lua;$LUA_PATH"
CKSUM="lua5.4 $D/cksum.lua"
TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT
printf 'hello world\n' > "$TMP"

# the published value for this text, and what the system says
[ "$($CKSUM < "$TMP")" = "3733384285 12" ] &&
[ "$($CKSUM "$TMP")" = "$(cksum "$TMP")" ] &&
[ "$(printf '' | $CKSUM)" = "$(printf '' | cksum)" ] &&
! $CKSUM -Z 2>/dev/null &&
! $CKSUM /nonexistent 2>/dev/null
