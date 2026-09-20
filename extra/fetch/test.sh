#!/bin/sh
# SPDX-License-Identifier: ISC
# fetch against a server on loopback, so the test needs no network.
D="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$D/../.." && pwd)"
command -v python3 >/dev/null 2>&1 || exit 77

export LUA_PATH="$ROOT/?.lua;$ROOT/?/init.lua;$LUA_PATH"
FETCH="lua5.4 $D/fetch.lua"
TMP=$(mktemp -d)
SERVER=
cleanup() {
	[ -n "$SERVER" ] && kill "$SERVER" 2>/dev/null
	rm -rf "$TMP"
}
trap cleanup EXIT

mkdir "$TMP/www"
printf 'hello over http\n' > "$TMP/www/hello.txt"
dd if=/dev/urandom of="$TMP/www/blob.bin" bs=1000 count=50 2>/dev/null

PORT=$((8000 + $$ % 1000))
(cd "$TMP/www" && python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1) &
SERVER=$!
n=0
while ! $FETCH "http://127.0.0.1:$PORT/hello.txt" >/dev/null 2>&1; do
	n=$((n + 1))
	[ "$n" -gt 50 ] && exit 1
	sleep 0.1
done

# a small body, and a big one that arrives in several reads
$FETCH "http://127.0.0.1:$PORT/hello.txt" > "$TMP/got.txt" || exit 1
cmp -s "$TMP/got.txt" "$TMP/www/hello.txt" || exit 1
$FETCH "http://127.0.0.1:$PORT/blob.bin" > "$TMP/got.bin" || exit 1
cmp -s "$TMP/got.bin" "$TMP/www/blob.bin" || exit 1

# -i prints the status line ahead of the body
$FETCH -i "http://127.0.0.1:$PORT/hello.txt" | head -1 | grep -q "^HTTP 200" || exit 1

# -O names the file after the url
(cd "$TMP" && $FETCH -qO "http://127.0.0.1:$PORT/hello.txt") || exit 1
cmp -s "$TMP/hello.txt" "$TMP/www/hello.txt" || exit 1

# a missing page is an error, and https says why it cannot
$FETCH "http://127.0.0.1:$PORT/nope" >/dev/null 2>&1 && exit 1
$FETCH "https://example.com/" >/dev/null 2>&1 && exit 1
exit 0
