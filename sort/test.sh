#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
SORT="lua5.4 $D/sort.lua"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf 'alpha 3\nbeta 1\ngamma 2\n' > "$TMP/data"
printf 'c:3:x\na:10:y\nb:2:z\n' > "$TMP/colon"
printf 'b\na\nB\nA\na\n' > "$TMP/words"

# the cases this had before: stdin, -n, -r, and a key with -n beside it
[ "$(printf 'b\na\nc\n' | $SORT)" = "$(printf 'a\nb\nc')" ] &&
[ "$(printf '10\n2\n1\n' | $SORT -n)" = "$(printf '1\n2\n10')" ] &&
[ "$(printf 'a\nb\nc\n' | $SORT -r)" = "$(printf 'c\nb\na')" ] &&
[ "$(printf 'b 2\na 3\nc 1\n' | $SORT -k 2 -n)" = "$(printf 'c 1\nb 2\na 3')" ] &&
[ "$($SORT "$TMP/data" | head -1)" = "alpha 3" ] &&
[ "$($SORT -r "$TMP/data" | head -1)" = "gamma 2" ] &&
# -k selects the field, attached or separate, with its own options
[ "$($SORT -k2n "$TMP/data" | head -1)" = "beta 1" ] &&
[ "$($SORT -k 2n "$TMP/data" | head -1)" = "beta 1" ] &&
[ "$($SORT -k2,2n "$TMP/data" | head -1)" = "beta 1" ] &&
[ "$($SORT -k2nr "$TMP/data" | head -1)" = "alpha 3" ] &&
# -t says what a field is, and a numeric key reads the number it starts with
[ "$($SORT -t: -k2n "$TMP/colon" | head -1)" = "b:2:z" ] &&
[ "$($SORT -t: -k2,2n "$TMP/colon" | tail -1)" = "a:10:y" ] &&
# several keys, in order
[ "$($SORT -k1,1 -k2,2n "$TMP/data" | head -1)" = "alpha 3" ] &&
# -u drops what the keys call equal, -f folds case
[ "$($SORT -u "$TMP/words" | wc -l)" = "4" ] &&
[ "$($SORT -fu "$TMP/words" | wc -l)" = "2" ] &&
# an unknown option is refused rather than ignored
! $SORT -Z "$TMP/data" 2>/dev/null
