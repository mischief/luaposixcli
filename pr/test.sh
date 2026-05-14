#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
OUT=$(printf "hello\n" | lua5.4 "$D/pr.lua" -)
echo "$OUT" | grep -q "Page 1" && echo "$OUT" | grep -q "hello"
