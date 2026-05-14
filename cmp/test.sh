#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
TMP1=$(mktemp); TMP2=$(mktemp)
echo "same" > "$TMP1"; echo "same" > "$TMP2"
lua5.4 "$D/cmp.lua" "$TMP1" "$TMP2"
RET1=$?
echo "diff" > "$TMP2"
lua5.4 "$D/cmp.lua" "$TMP1" "$TMP2" >/dev/null
RET2=$?
rm -f "$TMP1" "$TMP2"
[ $RET1 -eq 0 ] && [ $RET2 -eq 1 ]
