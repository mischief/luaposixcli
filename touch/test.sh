#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
TMP=$(mktemp -d)/newfile
lua5.4 "$D/touch.lua" "$TMP"
[ -f "$TMP" ]
RET=$?
rm -f "$TMP"
rmdir "$(dirname "$TMP")"
exit $RET
