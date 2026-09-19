#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
CAT="lua5.4 $D/cat.lua"
TMP=$(mktemp)
printf 'filecontent\n' > "$TMP"
[ "$(echo hello | $CAT)" = "hello" ] &&
[ "$($CAT "$TMP")" = "filecontent" ] &&
[ "$(printf 'a\nb\n' | $CAT -n)" = "$(printf '     1\ta\n     2\tb')" ] &&
[ "$(printf 'a\n\n\nb\n' | $CAT -s | wc -l)" = "3" ] &&
[ "$(printf 'a\n' | $CAT -e)" = 'a$' ] &&
[ "$(printf '\ta\n' | $CAT -t)" = '^Ia' ]
RET=$?
rm "$TMP"
exit $RET
