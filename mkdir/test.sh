#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
TMP=$(mktemp -d)/testdir
lua5.4 "$D/mkdir.lua" "$TMP"
[ -d "$TMP" ]
RET=$?
rmdir "$TMP"
rmdir "$(dirname "$TMP")"
exit $RET
