#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
[ "$(timeout 1 lua5.4 "$D/yes.lua" | head -1)" = "y" ] &&
[ "$(timeout 1 lua5.4 "$D/yes.lua" hi | head -1)" = "hi" ]
