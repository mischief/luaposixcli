#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
OUT=$(lua5.4 "$D/df.lua" /)
echo "$OUT" | grep -q "1K-blocks" && echo "$OUT" | grep -q "/"
