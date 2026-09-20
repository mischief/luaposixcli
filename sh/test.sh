#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
ROOT="$(cd "$D/.." && pwd)"
export LUA_PATH="$ROOT/?.lua:$ROOT/?/init.lua:$LUA_PATH"
SH="lua5.4 $D/sh.lua"
TMPH=$(mktemp -d)
trap 'rm -rf "$TMPH"' EXIT
printf 'PROFILE_RAN=yes\nexport PROFILE_RAN\n' > "$TMPH/.profile"
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
[ "$($SH -c "echo $ROOT/sh/e*.lua")" = "$ROOT/sh/env.lua $ROOT/sh/expand.lua" ] &&
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
[ "$($SH -c 'echo $((5>3))')" = "1" ] &&
# set builtin: positional parameters and options
[ "$($SH -c 'set -- x y z; echo "$# $1 $3"')" = "3 x z" ] &&
[ "$($SH -c 'set a b; echo "$# $1"')" = "2 a" ] &&
[ "$($SH -c 'set -- ; echo $#')" = "0" ] &&
[ "$($SH -c 'set -e; false; echo REACHED'; echo "rc=$?")" = "rc=1" ] &&
[ "$($SH -c 'set -e; if false; then echo no; fi; false || true; ! true; echo OK')" = "OK" ] &&
# field splitting on unquoted expansion
[ "$($SH -c 'v="a b"; printf "[%s]" $v')" = "[a][b]" ] &&
[ "$($SH -c 'v="a b"; printf "[%s]" "$v"')" = "[a b]" ] &&
[ "$($SH -c 'IFS=:; v=a:b; printf "[%s]" $v')" = "[a][b]" ] &&
[ "$($SH -c 'v=""; printf "[%s]" $v; echo done')" = "[]done" ] &&
[ "$($SH -c 'IFS=:; v=a:; printf "[%s]" $v')" = "[a]" ] &&
[ "$($SH -c 'IFS=:; v=a::b; printf "[%s]" $v')" = "[a][][b]" ] &&
[ "$($SH -c 'IFS=:; v=:a; printf "[%s]" $v')" = "[][a]" ] &&
[ "$($SH -c 'v="  a  b  "; printf "[%s]" $v')" = "[a][b]" ] &&
# nested double quotes inside command substitution
[ "$($SH -c 'echo "M: $(echo "a b")"')" = "M: a b" ] &&
[ "$($SH -c 'echo "$(echo ")")"')" = ")" ] &&
# prefix assignments are visible to later prefixes
[ "$($SH -c 'A=1 B=$A env' | grep "^B=")" = "B=1" ] &&
# ${var%pat} honours an escaped pattern character
[ "$($SH -c 'v="a*c"; echo "${v%\*c}"')" = "a" ] &&
# ${#param} works on special parameters too
[ "$($SH -c 'set -- ab cde; echo ${#0} ${#1} ${#2}' sh)" = "2 2 3" ] &&
# ${var:offset:length}
[ "$($SH -c 'v=abcdef; echo "${v:1:3} ${v: -2} ${v:-def}"')" = "bcd ef abcdef" ] &&
# ${var:?word} ends a non-interactive shell
[ "$($SH -c 'echo ${u:?boom}; echo AFTER' 2>/dev/null)" = "" ] &&
# arithmetic: C semantics, no Lua evaluation
[ "$($SH -c 'echo $((-7/2)) $((-7%2)) $((!0)) $((2 && 3)) $((010)) $((0x1f))')" = "-3 -1 1 1 8 31" ] &&
[ "$($SH -c 'A="math.pi"; echo $((A))' 2>/dev/null; echo "rc=$?")" = "rc=2" ] &&
[ "$($SH -c 'echo $((1/0))' 2>/dev/null; echo "rc=$?")" = "rc=2" ] &&
[ "$($SH -c 'echo $((1+))' 2>/dev/null; echo "rc=$?")" = "rc=2" ] &&
[ "$($SH -c 'a=0; echo $((a != 0 && 10/a > 1))')" = "0" ] &&
# here-document expansion and trailing newline
[ "$(printf 'x=world\ncat <<EOF\nH $((1+1)) $x\nEOF\necho next\n' | $SH)" = "$(printf 'H 2 world\nnext')" ] &&
[ "$(printf "cat <<'EOF'\nliteral \$x\nEOF\n" | $SH)" = 'literal $x' ] &&
[ "$(printf 'cat <<EOF\na\n\nb\nEOF\n' | $SH | wc -l)" = "3" ] &&
# a login shell reads the profiles, an ordinary one does not.
# /etc/profile is read first and may print anything, so match loosely.
HOME=$TMPH $SH -l -c 'echo $PROFILE_RAN' 2>/dev/null | grep -q yes &&
[ "$(HOME=$TMPH $SH -c 'echo $PROFILE_RAN' 2>/dev/null)" = "" ] &&
# exported variables reach a child process
[ "$($SH -c 'BAR=two; export BAR; env' | grep "^BAR=")" = "BAR=two" ] &&
[ "$($SH -c 'export BAZ=three; env' | grep "^BAZ=")" = "BAZ=three" ] &&
[ "$($SH -c 'X=1; env' | grep -c "^X=")" = "0" ] &&
[ "$($SH -c 'Z=zed; export Z; exec env' | grep "^Z=")" = "Z=zed" ] &&
[ "$($SH -c 'Y=why; export Y; command env' | grep "^Y=")" = "Y=why" ] &&
# echo -n
[ "$($SH -c 'echo -n a; echo b')" = "ab" ] &&
# pipeline SIGPIPE handling
[ "$(timeout 3 $SH -c 'yes | head -3')" = "$(printf 'y\ny\ny')" ] &&
[ "$(timeout 3 $SH -c 'seq 1000 | head -2')" = "$(printf '1\n2')" ]
