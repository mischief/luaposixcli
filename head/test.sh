#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
[ "$(seq 10 | lua5.4 "$D/head.lua" -3)" = "$(seq 10 | head -3)" ]
