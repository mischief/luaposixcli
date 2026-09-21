#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
# check +%Y produces a 4-digit year
OUT=$(lua5.4 "$D/date.lua" +%Y)
[ ${#OUT} -eq 4 ] && [ "$OUT" -gt 2000 ] &&
# -u is the same instant read in UTC
[ "$(lua5.4 "$D/date.lua" -u +%Y-%m-%dT%H)" = "$(date -u +%Y-%m-%dT%H)" ] &&
[ "$(lua5.4 "$D/date.lua" -u +%Z)" = "UTC" ] &&
! lua5.4 "$D/date.lua" -Z 2>/dev/null &&
# the set form: what is not a time at all is a usage error, and a time
# that is one reaches the clock, which only root may set
! lua5.4 "$D/date.lua" 999 2>/dev/null &&
! lua5.4 "$D/date.lua" 13011200 2>/dev/null &&
if [ "$(id -u)" != "0" ]; then
	lua5.4 "$D/date.lua" 010112002030 2>&1 | grep -q "not permitted"
else
	true
fi
