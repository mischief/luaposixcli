#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
TMP=$(mktemp -d)
touch "$TMP/afile" "$TMP/bfile" "$TMP/.hidden"

# test default (no dotfiles, space-separated)
OUT=$(lua5.4 "$D/ls.lua" "$TMP")
echo "$OUT" | grep -q "afile" || exit 1
echo "$OUT" | grep -q ".hidden" && exit 1

# test -a (shows dotfiles)
OUT=$(lua5.4 "$D/ls.lua" -a "$TMP")
echo "$OUT" | grep -q ".hidden" || exit 1

# test -1 (one per line)
LINES=$(lua5.4 "$D/ls.lua" -1 "$TMP" | wc -l)
[ "$LINES" -eq 2 ] || exit 1

# test -l (long format)
OUT=$(lua5.4 "$D/ls.lua" -l "$TMP")
echo "$OUT" | grep -q "^-" || exit 1
echo "$OUT" | grep -q "afile" || exit 1

# test single file
[ "$(lua5.4 "$D/ls.lua" "$TMP/afile")" = "$TMP/afile" ] || exit 1

# test single file -l
OUT=$(lua5.4 "$D/ls.lua" -l "$TMP/afile")
echo "$OUT" | grep -q "^-" || exit 1
echo "$OUT" | grep -q "$TMP/afile" || exit 1

# test nonexistent
lua5.4 "$D/ls.lua" /nonexistent_xyz 2>/dev/null
[ $? -eq 1 ] || exit 1

rm -rf "$TMP"
