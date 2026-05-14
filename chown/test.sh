#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
TMP=$(mktemp)
# chown to our own uid:gid (should always succeed)
lua5.4 "$D/chown.lua" "$(id -un):$(id -gn)" "$TMP"
RET=$?
rm -f "$TMP"
exit $RET
