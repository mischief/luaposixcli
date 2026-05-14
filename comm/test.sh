#!/bin/sh
# SPDX-License-Identifier: ISC
set -e
D="$(dirname "$0")"
DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

printf 'a\nb\nc\nd\n' > "$DIR/f1"
printf 'b\nc\ne\n' > "$DIR/f2"

# suppress col 1 and 2 (only common)
out=$(lua5.4 "$D/comm.lua" -12 "$DIR/f1" "$DIR/f2")
expected=$(printf 'b\nc')
[ "$out" = "$expected" ] || { echo "FAIL: -12"; exit 1; }

# suppress col 3 (only unique)
out=$(lua5.4 "$D/comm.lua" -3 "$DIR/f1" "$DIR/f2")
expected=$(printf 'a\nd\n\te')
[ "$out" = "$expected" ] || { echo "FAIL: -3"; exit 1; }

echo "PASS"
