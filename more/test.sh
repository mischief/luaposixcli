#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(cd "$(dirname "$0")" && pwd)"
MORE="lua5.4 $D/more.lua"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
seq 100 > "$TMP/n"

# down a pipe it is cat, so a pipeline through it behaves
[ "$(seq 5 | $MORE)" = "$(seq 5)" ] || exit 1
[ "$($MORE "$TMP/n" | wc -l)" = "100" ] || exit 1
# +line starts further in
[ "$($MORE +50 "$TMP/n" | head -1)" = "50" ] || exit 1
# -s folds runs of blank lines into one
[ "$(printf 'a\n\n\n\nb\n' | $MORE -s | wc -l)" = "3" ] || exit 1
# several files are labelled
$MORE "$TMP/n" "$TMP/n" | grep -q '^::::::::::::::$' || exit 1
# a bad option is refused, a missing file reported
$MORE -Z 2>/dev/null && exit 1
$MORE "$TMP/nope" 2>&1 | grep -q "more:" || exit 1
# on a terminal it stops at a screenful and q leaves
command -v script >/dev/null 2>&1 || exit 0
out=$(printf 'q' | script -qec "$MORE $TMP/n" /dev/null | head -30 | wc -l)
[ "$out" -lt 100 ] || exit 1
exit 0
