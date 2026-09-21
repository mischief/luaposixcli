#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
TMP=$(mktemp)
OUT=$(echo hello | lua5.4 "$D/tee.lua" "$TMP")
[ "$OUT" = "hello" ] && [ "$(cat "$TMP")" = "hello" ]
RET=$?
rm "$TMP"
exit $RET &&
# -a appends rather than truncating, and an unknown option is refused
TMPT=$(mktemp) &&
printf 'one\n' | lua5.4 "$D/tee.lua" "$TMPT" >/dev/null &&
printf 'two\n' | lua5.4 "$D/tee.lua" -a "$TMPT" >/dev/null &&
[ "$(wc -l < "$TMPT")" = "2" ] &&
! lua5.4 "$D/tee.lua" -Z </dev/null 2>/dev/null &&
rm -f "$TMPT"
