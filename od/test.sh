#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
OUT=$(printf "AB" | lua5.4 "$D/od.lua")
echo "$OUT" | grep -q "^0000000" && echo "$OUT" | grep -q "0000002"
