#!/bin/sh
# SPDX-License-Identifier: ISC
# sz and rz against lrzsz, each pair on the ends of a pty pair.
D="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$D/../.." && pwd)"
command -v lrz >/dev/null 2>&1 || exit 77
command -v lsz >/dev/null 2>&1 || exit 77

export LUA_PATH="$ROOT/?.lua;$ROOT/?/init.lua;$LUA_PATH"
PAIR="lua5.4 $D/pty_pair.lua"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/send" "$TMP/recv"
printf 'hello zmodem\n' > "$TMP/send/hello.txt"
dd if=/dev/urandom of="$TMP/send/blob.bin" bs=1000 count=20 2>/dev/null

# our sender, lrzsz receiver
$PAIR "lua5.4 $D/sz.lua hello.txt blob.bin" "$TMP/send" "lrz -y" "$TMP/recv" >/dev/null 2>&1
cmp -s "$TMP/send/hello.txt" "$TMP/recv/hello.txt" || exit 1
cmp -s "$TMP/send/blob.bin" "$TMP/recv/blob.bin" || exit 1

# lrzsz sender, our receiver
rm -f "$TMP/recv"/*
$PAIR "lsz hello.txt blob.bin" "$TMP/send" "lua5.4 $D/../rz/rz.lua" "$TMP/recv" >/dev/null 2>&1
cmp -s "$TMP/send/hello.txt" "$TMP/recv/hello.txt" || exit 1
cmp -s "$TMP/send/blob.bin" "$TMP/recv/blob.bin" || exit 1
exit 0
