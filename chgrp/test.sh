#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
TMP=$(mktemp)
# chgrp to our own group (should always succeed)
lua5.4 "$D/chgrp.lua" "$(id -gn)" "$TMP"
RET=$?
rm -f "$TMP"
exit $RET
