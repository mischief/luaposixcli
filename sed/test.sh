#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
SED="lua5.4 $D/sed.lua"
TMP=$(mktemp -d)
printf 'a1\na2\n' > "$TMP/f1"
printf 'b1\nb2\n' > "$TMP/f2"

[ "$(printf 'hello world\n' | $SED 's/world/earth/')" = "hello earth" ] &&
[ "$(printf 'a\nb\nc\n' | $SED '2d')" = "$(printf 'a\nc')" ] &&
[ "$(printf 'aaa\n' | $SED 's/a/b/g')" = "bbb" ] &&
[ "$(printf 'hello\nworld\n' | $SED -n '/world/p')" = "world" ] &&
[ "$(printf 'foo\nbar\n' | $SED -e 's/foo/baz/' -e 's/bar/qux/')" = "$(printf 'baz\nqux')" ] &&
# several operands are one stream: line numbers run on and $ is the last line
[ "$($SED -n p "$TMP/f1" "$TMP/f2")" = "$(printf 'a1\na2\nb1\nb2')" ] &&
[ "$($SED -n '3p' "$TMP/f1" "$TMP/f2")" = "b1" ] &&
[ "$($SED -n '$p' "$TMP/f1" "$TMP/f2")" = "b2" ] &&
[ "$($SED '1q' "$TMP/f1" "$TMP/f2")" = "a1" ] &&
# an unreadable operand is reported, the rest still run
[ "$($SED -n p "$TMP/f1" "$TMP/nope" "$TMP/f2" 2>/dev/null)" = "$(printf 'a1\na2\nb1\nb2')" ] &&
! $SED -n p "$TMP/nope" 2>/dev/null
RET=$?
rm -rf "$TMP"
exit $RET
