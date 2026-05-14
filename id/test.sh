#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
OUT=$(lua5.4 "$D/id.lua")
echo "$OUT" | grep -q "uid=" && echo "$OUT" | grep -q "gid="
