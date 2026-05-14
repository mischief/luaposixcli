#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
F=$(lua5.4 "$D/mktemp.lua")
[ -f "$F" ]
RET=$?
rm -f "$F"
exit $RET
