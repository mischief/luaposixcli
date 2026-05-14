#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
TMP=$(mktemp)
LINK="${TMP}_link"
lua5.4 "$D/ln.lua" "$TMP" "$LINK"
[ -f "$LINK" ]
RET=$?
rm -f "$TMP" "$LINK"
exit $RET
