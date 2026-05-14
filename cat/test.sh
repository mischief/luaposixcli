#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
TMP=$(mktemp)
echo "filecontent" > "$TMP"
[ "$(echo hello | lua5.4 "$D/cat.lua")" = "hello" ] &&
[ "$(lua5.4 "$D/cat.lua" "$TMP")" = "filecontent" ]
RET=$?
rm "$TMP"
exit $RET
