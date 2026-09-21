#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
TMP=$(mktemp -d)/newfile
lua5.4 "$D/touch.lua" "$TMP"
[ -f "$TMP" ]
RET=$?
rm -f "$TMP"
rmdir "$(dirname "$TMP")"
exit $RET &&
# -c leaves a missing file missing, -t sets the time, -r copies one
TMPD=$(mktemp -d) &&
lua5.4 "$D/touch.lua" -c "$TMPD/nothere" && [ ! -e "$TMPD/nothere" ] &&
lua5.4 "$D/touch.lua" -t 202001020304 "$TMPD/stamped" &&
touch -t 202001020304 "$TMPD/sys" &&
[ "$(stat -c%Y "$TMPD/stamped")" = "$(stat -c%Y "$TMPD/sys")" ] &&
lua5.4 "$D/touch.lua" -r "$TMPD/sys" "$TMPD/ref" &&
[ "$(stat -c%Y "$TMPD/ref")" = "$(stat -c%Y "$TMPD/sys")" ] &&
! lua5.4 "$D/touch.lua" -Z x 2>/dev/null &&
! lua5.4 "$D/touch.lua" 2>/dev/null &&
rm -rf "$TMPD"
