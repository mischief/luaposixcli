#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
# check +%Y produces a 4-digit year
OUT=$(lua5.4 "$D/date.lua" +%Y)
[ ${#OUT} -eq 4 ] && [ "$OUT" -gt 2000 ]
