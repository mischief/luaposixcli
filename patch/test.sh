#!/bin/sh
# SPDX-License-Identifier: ISC
set -e
D="$(cd "$(dirname "$0")" && pwd)"
DIFF="lua5.4 $(dirname "$D")/diff/diff.lua"
PATCH="lua5.4 $D/patch.lua"
DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

printf 'line1\nline2\nline3\nline4\nline5\n' > "$DIR/file"
printf 'line1\nmodified\nline3\nnew line\nline4\nline5\n' > "$DIR/file.new"

# Generate patch (use relative names by cd'ing into DIR)
(cd "$DIR" && $DIFF -u file file.new > p.patch || true)

# Restore original
cp "$DIR/file" "$DIR/file.bak"

# Apply patch
(cd "$DIR" && $PATCH -p0 -i p.patch < /dev/null)
[ "$(cat "$DIR/file")" = "$(cat "$DIR/file.new")" ] || { echo "FAIL: apply"; exit 1; }

# Reverse patch
(cd "$DIR" && $PATCH -R -p0 -i p.patch < /dev/null)
[ "$(cat "$DIR/file")" = "$(cat "$DIR/file.bak")" ] || { echo "FAIL: reverse"; exit 1; }

echo "PASS"
