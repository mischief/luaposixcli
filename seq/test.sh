#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
[ "$(lua5.4 "$D/seq.lua" 5)" = "$(seq 5)" ] &&
[ "$(lua5.4 "$D/seq.lua" 2 5)" = "$(seq 2 5)" ] &&
[ "$(lua5.4 "$D/seq.lua" 1 2 9)" = "$(seq 1 2 9)" ]
