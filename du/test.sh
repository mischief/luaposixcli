#!/bin/sh
# SPDX-License-Identifier: ISC
set -e
D="$(dirname "$0")"
DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

mkdir -p "$DIR/sub"
dd if=/dev/zero of="$DIR/file1" bs=1024 count=4 2>/dev/null
dd if=/dev/zero of="$DIR/sub/file2" bs=1024 count=8 2>/dev/null

# -s shows summary only
out=$(lua5.4 "$D/du.lua" -s "$DIR" | awk '{print $1}')
[ "$out" -gt 0 ] || { echo "FAIL: -s returned 0"; exit 1; }

# -k uses 1024-byte blocks
out=$(lua5.4 "$D/du.lua" -sk "$DIR" | awk '{print $1}')
[ "$out" -ge 12 ] || { echo "FAIL: -sk too small ($out)"; exit 1; }

# without -s shows subdirectories
lines=$(lua5.4 "$D/du.lua" "$DIR" | wc -l)
[ "$lines" -ge 2 ] || { echo "FAIL: should show subdirs ($lines)"; exit 1; }

# -h produces human-readable
out=$(lua5.4 "$D/du.lua" -sh "$DIR" | awk '{print $1}')
echo "$out" | grep -qE '[0-9.]+[KMG]?' || { echo "FAIL: -h format ($out)"; exit 1; }

echo "PASS"
