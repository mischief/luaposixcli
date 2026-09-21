#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
# check +%Y produces a 4-digit year
OUT=$(lua5.4 "$D/date.lua" +%Y)
[ ${#OUT} -eq 4 ] && [ "$OUT" -gt 2000 ] &&
# -u is the same instant read in UTC
[ "$(lua5.4 "$D/date.lua" -u +%Y-%m-%dT%H)" = "$(date -u +%Y-%m-%dT%H)" ] &&
[ "$(lua5.4 "$D/date.lua" -u +%Z)" = "UTC" ] &&
! lua5.4 "$D/date.lua" -Z 2>/dev/null
