#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
TMP=$(mktemp -d)
lua5.4 "$D/rmdir.lua" "$TMP"
[ ! -d "$TMP" ]
