#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
TMP=$(mktemp)
LINK="${TMP}_hl"
lua5.4 "$D/link.lua" "$TMP" "$LINK"
[ -f "$LINK" ]
RET=$?
rm -f "$TMP" "$LINK"
exit $RET
