#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
TMP=$(mktemp -d)/testfifo
lua5.4 "$D/mkfifo.lua" "$TMP"
[ -p "$TMP" ]
RET=$?
rm -f "$TMP"
rmdir "$(dirname "$TMP")"
exit $RET
