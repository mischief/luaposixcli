#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
ROOT="$(cd "$D/../.." && pwd)"
export LUA_PATH="$ROOT/?.lua;$ROOT/?/init.lua;$LUA_PATH"
GZIP="lua5.4 $D/gzip.lua"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

seq 500 > "$TMP/plain"
head -c 20000 /dev/urandom > "$TMP/binary"
: > "$TMP/empty"

ok=0
for f in plain binary empty; do
	# our output is readable by the system gzip, and by us
	$GZIP -c "$TMP/$f" > "$TMP/$f.gz" || exit 1
	$GZIP -dc "$TMP/$f.gz" | cmp -s - "$TMP/$f" || exit 1
	gzip -dc "$TMP/$f.gz" | cmp -s - "$TMP/$f" || exit 1
	# and the system gzip's output is readable by us
	gzip -c "$TMP/$f" > "$TMP/$f.sys.gz" || exit 1
	$GZIP -dc "$TMP/$f.sys.gz" | cmp -s - "$TMP/$f" || exit 1
	ok=$((ok + 1))
done
[ "$ok" = 3 ] || exit 1

# stdin to stdout
[ "$(printf 'hello\n' | $GZIP | $GZIP -d)" = "hello" ] || exit 1
# a corrupt stream is refused
printf 'not a gzip file\n' | $GZIP -d 2>/dev/null && exit 1

# file in place: the original goes away, .gz appears, and back again
cp "$TMP/plain" "$TMP/work"
$GZIP "$TMP/work" || exit 1
[ -f "$TMP/work.gz" ] && [ ! -f "$TMP/work" ] || exit 1
$GZIP -d "$TMP/work.gz" || exit 1
cmp -s "$TMP/work" "$TMP/plain" || exit 1
[ ! -f "$TMP/work.gz" ] || exit 1
# -k keeps the input
$GZIP -k "$TMP/work" || exit 1
[ -f "$TMP/work" ] && [ -f "$TMP/work.gz" ] || exit 1
# an existing target is not overwritten without -f
$GZIP "$TMP/work" 2>/dev/null && exit 1
$GZIP -f "$TMP/work" || exit 1
# concatenated members decompress as one stream
cat "$TMP/work.gz" "$TMP/work.gz" > "$TMP/two.gz"
[ "$($GZIP -dc "$TMP/two.gz" | wc -l)" = "1000" ] || exit 1
exit 0
