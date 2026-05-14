#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
[ "$(printf 'hello\nworld\n' | lua5.4 "$D/grep.lua" "llo")" = "hello" ] &&
[ "$(printf 'Hello\nworld\n' | lua5.4 "$D/grep.lua" -i "HELLO")" = "Hello" ] &&
[ "$(printf 'a\nb\nc\n' | lua5.4 "$D/grep.lua" -v "b")" = "$(printf 'a\nc')" ] &&
[ "$(printf 'foo\nbar\nfoo\n' | lua5.4 "$D/grep.lua" -c "foo")" = "2" ] &&
[ "$(printf 'abc\ndef\n' | lua5.4 "$D/grep.lua" -E "^d.f")" = "def" ] &&
[ "$(printf 'abc\ndef\n' | lua5.4 "$D/grep.lua" -F "bc")" = "abc" ]
