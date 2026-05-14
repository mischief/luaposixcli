#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
ROOT="$(cd "$D/.." && pwd)"
export LUA_PATH="$ROOT/?.lua;$ROOT/?/init.lua;;"
SH="lua5.4 $D/sh.lua"
[ "$($SH -c 'echo hello world')" = "hello world" ] &&
[ "$($SH -c 'echo hello | cat')" = "hello" ] &&
[ "$($SH -c 'seq 5 | tail -2')" = "$(seq 5 | tail -2)" ] &&
[ "$($SH -c 'umask 077; umask')" = "0077" ] &&
# quoting tests
[ "$($SH -c 'echo "/etc/passwd"')" = "/etc/passwd" ] &&
[ "$($SH -c "echo 'hello/world'")" = "hello/world" ] &&
[ "$($SH -c 'echo "hello\"world"')" = 'hello"world' ] &&
[ "$($SH -c 'echo "back\\slash"')" = 'back\slash' ] &&
[ "$($SH -c "echo 'quotes \"inside\" singles'")" = 'quotes "inside" singles' ]
