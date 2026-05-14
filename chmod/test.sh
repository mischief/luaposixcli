#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
TMP=$(mktemp)
lua5.4 "$D/chmod.lua" 755 "$TMP"
[ -x "$TMP" ]
RET=$?
rm -f "$TMP"
exit $RET
