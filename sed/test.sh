#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
[ "$(printf 'hello world\n' | lua5.4 "$D/sed.lua" 's/world/earth/')" = "hello earth" ] &&
[ "$(printf 'a\nb\nc\n' | lua5.4 "$D/sed.lua" '2d')" = "$(printf 'a\nc')" ] &&
[ "$(printf 'aaa\n' | lua5.4 "$D/sed.lua" 's/a/b/g')" = "bbb" ] &&
[ "$(printf 'hello\nworld\n' | lua5.4 "$D/sed.lua" -n '/world/p')" = "world" ] &&
[ "$(printf 'foo\nbar\n' | lua5.4 "$D/sed.lua" -e 's/foo/baz/' -e 's/bar/qux/')" = "$(printf 'baz\nqux')" ]
