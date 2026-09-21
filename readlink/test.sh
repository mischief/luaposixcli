#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(cd "$(dirname "$0")" && pwd)"
READLINK="lua5.4 $D/readlink.lua"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 1
echo x > file
ln -s file one
ln -s one two

[ "$($READLINK one)" = "file" ] || exit 1
[ "$($READLINK two)" = "one" ] || exit 1
# -f walks the chain to something real
[ "$($READLINK -f two)" = "$TMP/file" ] || exit 1
# -n leaves the newline off
[ "$($READLINK -n one | wc -l)" = "0" ] || exit 1
# something that is not a link is an error, quiet with -q
$READLINK file 2>/dev/null && exit 1
[ "$($READLINK -q file 2>&1)" = "" ] || exit 1
$READLINK 2>/dev/null && exit 1
# and the system agrees where it has one
if command -v readlink >/dev/null 2>&1; then
	[ "$($READLINK one)" = "$(readlink one)" ] || exit 1
	[ "$($READLINK -f two)" = "$(readlink -f two)" ] || exit 1
fi
exit 0
