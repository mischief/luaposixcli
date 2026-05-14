#!/bin/sh
# SPDX-License-Identifier: ISC
set -e
D="$(cd "$(dirname "$0")" && pwd)"
DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

# Create test files
mkdir -p "$DIR/src/sub"
echo "hello" > "$DIR/src/a.txt"
echo "world" > "$DIR/src/sub/b.txt"
ln -s ../a.txt "$DIR/src/sub/link"

# Test create (use relative path)
(cd "$DIR" && lua5.4 "$D/tar.lua" cf "$DIR/test.tar" src)
[ -f "$DIR/test.tar" ] || { echo "FAIL: create"; exit 1; }

# Test list
out=$(lua5.4 "$D/tar.lua" tf "$DIR/test.tar")
echo "$out" | grep -q "a.txt" || { echo "FAIL: list a.txt"; exit 1; }
echo "$out" | grep -q "sub/b.txt" || { echo "FAIL: list sub/b.txt"; exit 1; }

# Test extract
mkdir "$DIR/dst"
(cd "$DIR/dst" && lua5.4 "$D/tar.lua" xf "$DIR/test.tar")
[ "$(cat "$DIR/dst/src/a.txt")" = "hello" ] || { echo "FAIL: extract a.txt"; exit 1; }
[ "$(cat "$DIR/dst/src/sub/b.txt")" = "world" ] || { echo "FAIL: extract sub/b.txt"; exit 1; }
[ -L "$DIR/dst/src/sub/link" ] || { echo "FAIL: extract symlink"; exit 1; }

# Test interop: our tar readable by system tar
out=$(tar tf "$DIR/test.tar" 2>/dev/null | grep "a.txt")
[ -n "$out" ] || { echo "FAIL: system tar can't read"; exit 1; }

# Test interop: system tar readable by us
(cd "$DIR/src" && tar cf "$DIR/sys.tar" a.txt sub 2>/dev/null)
out=$(lua5.4 "$D/tar.lua" tf "$DIR/sys.tar")
echo "$out" | grep -q "a.txt" || { echo "FAIL: read system tar"; exit 1; }

echo "PASS"
