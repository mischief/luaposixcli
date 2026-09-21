#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$D/.." && pwd)"
export LUA_PATH="$ROOT/?.lua;$LUA_PATH"
PATHCHK="lua5.4 $D/pathchk.lua"

$PATHCHK /usr/bin/lua &&
$PATHCHK -p ordinary/path &&
! $PATHCHK "" 2>/dev/null &&
# -p refuses what is not portable, and a very long component
! $PATHCHK -p 'has spaces/in it' 2>/dev/null &&
! $PATHCHK -p "$(printf 'a%.0s' $(seq 1 20))" 2>/dev/null &&
! $PATHCHK 2>/dev/null &&
! $PATHCHK -Z x 2>/dev/null
