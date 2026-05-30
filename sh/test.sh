#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
ROOT="$(cd "$D/.." && pwd)"
export LUA_PATH="$ROOT/?.lua:$ROOT/?/init.lua:$LUA_PATH"
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
[ "$($SH -c "echo 'quotes \"inside\" singles'")" = 'quotes "inside" singles' ] &&
# glob tests (use absolute path since meson may run from build dir)
[ "$($SH -c "echo $ROOT/sh/e*.lua")" = "$ROOT/sh/env.lua $ROOT/sh/exec.lua $ROOT/sh/expand.lua" ] &&
[ "$($SH -c 'echo "sh/*.lua"')" = "sh/*.lua" ] &&
[ "$($SH -c "echo $ROOT/sh/[el]*.lua" | wc -w)" -gt 3 ] &&
# read builtin
[ "$(printf 'hello world\n' | $SH -c 'read a b; echo $a $b')" = "hello world" ] &&
[ "$(printf 'hello world\n' | $SH -c 'read; echo $REPLY')" = "hello world" ] &&
[ "$(printf 'a:b:c\n' | $SH -c 'IFS=: read x y z; echo $x $y $z')" = "a b c" ] &&
[ "$(printf 'hello\\\\world\n' | $SH -c 'read -r x; echo $x')" = 'hello\\world' ] &&
[ "$(printf '' | $SH -c 'read x; echo $?')" = "1" ] &&
# subshell ()
[ "$(printf 'x=hello\n(x=world; echo $x)\necho $x\n' | $SH)" = "$(printf 'world\nhello')" ] &&
[ "$($SH -c '(echo sub)')" = "sub" ] &&
# brace group {}
[ "$(printf 'x=hello\n{ x=world; echo $x; }\necho $x\n' | $SH)" = "$(printf 'world\nworld')" ] &&
[ "$($SH -c '{ echo one; echo two; }')" = "$(printf 'one\ntwo')" ] &&
# case/esac
[ "$($SH -c 'case hello in hello) echo matched;; *) echo nope;; esac')" = "matched" ] &&
[ "$($SH -c 'case foo.c in *.c) echo c;; *.h) echo h;; esac')" = "c" ] &&
[ "$($SH -c 'case xyz in a) echo a;; *) echo default;; esac')" = "default" ] &&
# getopts
[ "$(printf 'OPTIND=1\nwhile getopts "ab:" opt -a -b val; do\ncase $opt in\na) echo got_a;;\nb) echo got_b=$OPTARG;;\nesac\ndone\n' | $SH)" = "$(printf 'got_a\ngot_b=val')" ] &&
# functions
[ "$($SH -c 'f() { echo hi; }; f')" = "hi" ] &&
[ "$($SH -c 'add() { echo $1 $2; }; add hello world')" = "hello world" ] &&
[ "$(printf 'greet() {\n  echo hello $1\n}\ngreet earth\n' | $SH)" = "hello earth" ] &&
# $1-$9 positional params
[ "$($SH -c 'echo $1' sh foo)" = "foo" ] &&
# trap
[ "$($SH -c 'trap "echo bye" EXIT; echo hi')" = "$(printf 'hi\nbye')" ] &&
# here-documents
[ "$(printf 'cat <<EOF\nhello world\nEOF\n' | $SH)" = "hello world" ] &&
[ "$(printf 'cat <<EOF\nline1\nline2\nEOF\n' | $SH)" = "$(printf 'line1\nline2')" ] &&
# arithmetic expansion
[ "$($SH -c 'echo $((1+2))')" = "3" ] &&
[ "$($SH -c 'echo $((3*4+1))')" = "13" ] &&
[ "$($SH -c 'x=10; echo $((x+5))')" = "15" ] &&
[ "$($SH -c 'echo $((10%3))')" = "1" ] &&
[ "$($SH -c 'echo $((5>3))')" = "1" ]
