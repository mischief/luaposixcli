#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
TMP=$(mktemp)
lua5.4 "$D/rm.lua" "$TMP"
[ ! -f "$TMP" ] &&
lua5.4 "$D/rm.lua" -f /nonexistent_xyz &&
# -r takes a tree, a directory without it is an error, -f is silent
TMPD=$(mktemp -d) &&
mkdir -p "$TMPD/a/b" && : > "$TMPD/a/b/f" &&
! lua5.4 "$D/rm.lua" "$TMPD/a" 2>/dev/null &&
lua5.4 "$D/rm.lua" -r "$TMPD/a" && [ ! -d "$TMPD/a" ] &&
lua5.4 "$D/rm.lua" -f "$TMPD/gone" &&
! lua5.4 "$D/rm.lua" -Z 2>/dev/null &&
rmdir "$TMPD"
