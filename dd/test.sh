#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
TMP_IN=$(mktemp); TMP_OUT=$(mktemp)
echo "abcdefghij" > "$TMP_IN"
lua5.4 "$D/dd.lua" if="$TMP_IN" of="$TMP_OUT" bs=5 count=1 2>/dev/null
[ "$(cat "$TMP_OUT")" = "abcde" ]
RET=$?
rm -f "$TMP_IN" "$TMP_OUT"
exit $RET
