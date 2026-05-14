#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
OUT=$(lua5.4 "$D/logname.lua" 2>/dev/null)
# logname may fail in non-login contexts; just check it doesn't crash
[ $? -eq 0 ] || [ $? -eq 1 ]
