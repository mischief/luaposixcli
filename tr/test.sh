#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
[ "$(printf 'hello' | lua5.4 "$D/tr.lua" a-z A-Z)" = "HELLO" ] &&
[ "$(printf 'hello' | lua5.4 "$D/tr.lua" -d l)" = "heo" ] &&
[ "$(printf 'aabbc' | lua5.4 "$D/tr.lua" -s a-z)" = "abc" ]
