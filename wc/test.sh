#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
[ "$(printf 'one\ntwo\nthr\n' | lua5.4 "$D/wc.lua")" = "       3       3      12 " ]
