#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
OUT=$(lua5.4 "$D/nohup.lua" echo hello 2>/dev/null)
[ "$OUT" = "hello" ]
