#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
CHMOD="lua5.4 $D/chmod.lua"
TMP=$(mktemp)
mode() { ls -l "$1" | cut -c2-10; }

$CHMOD 755 "$TMP" && [ -x "$TMP" ] &&
$CHMOD 644 "$TMP" && [ "$(mode "$TMP")" = "rw-r--r--" ] &&
# symbolic modes
$CHMOD +x "$TMP" && [ -x "$TMP" ] &&
$CHMOD go-w "$TMP" && [ "$(mode "$TMP")" = "rwxr-xr-x" ] &&
$CHMOD a=r "$TMP" && [ "$(mode "$TMP")" = "r--r--r--" ] &&
$CHMOD u=rwx,g=rx,o= "$TMP" && [ "$(mode "$TMP")" = "rwxr-x---" ] &&
$CHMOD o=u "$TMP" && [ "$(mode "$TMP")" = "rwxr-xrwx" ] &&
$CHMOD u-w "$TMP" && [ "$(mode "$TMP")" = "r-xr-xrwx" ] &&
# an invalid mode is rejected
! $CHMOD bogus "$TMP" 2>/dev/null
RET=$?
rm -f "$TMP"
exit $RET
