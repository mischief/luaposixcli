#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
TMP=$(mktemp)
lua5.4 "$D/unlink.lua" "$TMP"
[ ! -f "$TMP" ]
