#!/bin/sh
# SPDX-License-Identifier: ISC
set -e
D="$(cd "$(dirname "$0")" && pwd)"
DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

printf 'a\nb\nc\nd\ne\n' > "$DIR/f1"
printf 'a\nB\nc\nd\nf\n' > "$DIR/f2"

# Unified diff
out=$(lua5.4 "$D/diff.lua" -u "$DIR/f1" "$DIR/f2" || true)
echo "$out" | grep -q "^-b" || { echo "FAIL: unified -b"; exit 1; }
echo "$out" | grep -q "^+B" || { echo "FAIL: unified +B"; exit 1; }
echo "$out" | grep -q "^@@" || { echo "FAIL: unified @@"; exit 1; }

# Normal diff
out=$(lua5.4 "$D/diff.lua" "$DIR/f1" "$DIR/f2" || true)
echo "$out" | grep -q "c" || { echo "FAIL: normal change"; exit 1; }

# Identical files
lua5.4 "$D/diff.lua" "$DIR/f1" "$DIR/f1" && echo "identical ok" || { echo "FAIL: identical"; exit 1; }

# Addition only
printf 'a\nb\n' > "$DIR/f3"
printf 'a\nb\nc\n' > "$DIR/f4"
out=$(lua5.4 "$D/diff.lua" -u "$DIR/f3" "$DIR/f4" || true)
echo "$out" | grep -q "^+c" || { echo "FAIL: addition"; exit 1; }

echo "PASS"
