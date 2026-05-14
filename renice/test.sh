#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
# renice our own process by 0 (should succeed)
lua5.4 "$D/renice.lua" -n 0 -p $$
