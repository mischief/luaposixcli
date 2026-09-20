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

# Test gzip: create, list, extract
(cd "$DIR" && lua5.4 "$D/tar.lua" czf "$DIR/test.tgz" src)
[ -f "$DIR/test.tgz" ] || { echo "FAIL: create compressed"; exit 1; }
[ "$(stat -c%s "$DIR/test.tgz")" -lt "$(stat -c%s "$DIR/test.tar")" ] ||
	{ echo "FAIL: compressed archive is not smaller"; exit 1; }
out=$(lua5.4 "$D/tar.lua" tzf "$DIR/test.tgz")
echo "$out" | grep -q "sub/b.txt" || { echo "FAIL: list compressed"; exit 1; }

# gzip is recognized by its magic, so -z is not needed to read
out=$(lua5.4 "$D/tar.lua" tf "$DIR/test.tgz")
echo "$out" | grep -q "sub/b.txt" || { echo "FAIL: detect compressed"; exit 1; }

mkdir "$DIR/dstz"
(cd "$DIR/dstz" && lua5.4 "$D/tar.lua" xzf "$DIR/test.tgz")
[ "$(cat "$DIR/dstz/src/sub/b.txt")" = "world" ] || { echo "FAIL: extract compressed"; exit 1; }

# Interop both ways for the compressed form
tar tzf "$DIR/test.tgz" | grep -q "a.txt" || { echo "FAIL: system tar can't read ours"; exit 1; }
(cd "$DIR/src" && tar czf "$DIR/sys.tgz" a.txt sub 2>/dev/null)
out=$(lua5.4 "$D/tar.lua" tzf "$DIR/sys.tgz")
echo "$out" | grep -q "a.txt" || { echo "FAIL: read system tar.gz"; exit 1; }

# Through a pipe
(cd "$DIR" && lua5.4 "$D/tar.lua" czf - src) > "$DIR/pipe.tgz"
out=$(lua5.4 "$D/tar.lua" tzf - < "$DIR/pipe.tgz")
echo "$out" | grep -q "a.txt" || { echo "FAIL: compressed through a pipe"; exit 1; }

echo "PASS"
