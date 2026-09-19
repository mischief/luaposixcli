#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
WC="lua5.4 $D/wc.lua"
TMP=$(mktemp)
printf 'a b\nc\n' > "$TMP"
[ "$(printf 'one\ntwo\nthr\n' | $WC)" = "       3       3      12 " ] &&
[ "$($WC -l "$TMP")" = "       2 $TMP" ] &&
[ "$($WC -c "$TMP")" = "       6 $TMP" ] &&
[ "$($WC -w "$TMP")" = "       3 $TMP" ] &&
[ "$($WC -lw "$TMP")" = "       2       3 $TMP" ]
RET=$?
rm "$TMP"
exit $RET
