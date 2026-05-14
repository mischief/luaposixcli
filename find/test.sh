#!/bin/sh
# SPDX-License-Identifier: ISC
set -e
D="$(dirname "$0")"
DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

mkdir -p "$DIR/a/b"
touch "$DIR/a/f1.txt" "$DIR/a/f2.log" "$DIR/a/b/f3.txt"

# find all files
out=$(lua5.4 "$D/find.lua" "$DIR" -type f | wc -l)
[ "$out" -eq 3 ] || { echo "FAIL: type f count ($out)"; exit 1; }

# find by name
out=$(lua5.4 "$D/find.lua" "$DIR" -name "*.txt" -type f | wc -l)
[ "$out" -eq 2 ] || { echo "FAIL: name *.txt ($out)"; exit 1; }

# find directories
out=$(lua5.4 "$D/find.lua" "$DIR" -type d | wc -l)
[ "$out" -eq 3 ] || { echo "FAIL: type d ($out)"; exit 1; }

# maxdepth
out=$(lua5.4 "$D/find.lua" "$DIR" -maxdepth 1 | wc -l)
[ "$out" -eq 2 ] || { echo "FAIL: maxdepth ($out)"; exit 1; }

echo "PASS"
