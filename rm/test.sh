#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
TMP=$(mktemp)
lua5.4 "$D/rm.lua" "$TMP"
[ ! -f "$TMP" ] &&
lua5.4 "$D/rm.lua" -f /nonexistent_xyz
