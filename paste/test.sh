#!/bin/sh
# SPDX-License-Identifier: ISC
set -e
D="$(dirname "$0")"
DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

printf 'a\nb\nc\n' > "$DIR/f1"
printf '1\n2\n3\n' > "$DIR/f2"

# basic paste
out=$(lua5.4 "$D/paste.lua" "$DIR/f1" "$DIR/f2")
[ "$out" = "$(printf 'a\t1\nb\t2\nc\t3')" ] || { echo "FAIL: basic paste"; exit 1; }

# custom delimiter
out=$(lua5.4 "$D/paste.lua" -d: "$DIR/f1" "$DIR/f2")
[ "$out" = "$(printf 'a:1\nb:2\nc:3')" ] || { echo "FAIL: -d"; exit 1; }

# serial mode
out=$(lua5.4 "$D/paste.lua" -s "$DIR/f1")
[ "$out" = "$(printf 'a\tb\tc')" ] || { echo "FAIL: -s"; exit 1; }

echo "PASS"
