#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
TMP=$(mktemp)
OUT=$(echo hello | lua5.4 "$D/tee.lua" "$TMP")
[ "$OUT" = "hello" ] && [ "$(cat "$TMP")" = "hello" ]
RET=$?
rm "$TMP"
exit $RET
