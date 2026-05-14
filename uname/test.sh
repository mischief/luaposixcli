#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
[ "$(lua5.4 "$D/uname.lua")" = "$(uname -s)" ] &&
[ "$(lua5.4 "$D/uname.lua" -m)" = "$(uname -m)" ]
