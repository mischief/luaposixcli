#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
OUT=$(lua5.4 "$D/time.lua" true 2>&1)
echo "$OUT" | grep -q "real"
