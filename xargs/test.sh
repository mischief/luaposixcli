#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
[ "$(printf 'a b c\n' | lua5.4 "$D/xargs.lua" echo)" = "a b c" ] &&
[ "$(printf 'a\nb\nc\n' | lua5.4 "$D/xargs.lua" -n1 echo)" = "$(printf 'a\nb\nc')" ]
