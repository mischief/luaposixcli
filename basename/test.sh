#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
[ "$(lua5.4 "$D/basename.lua" /foo/bar/baz)" = "baz" ] &&
[ "$(lua5.4 "$D/basename.lua" /foo/bar/baz.txt .txt)" = "baz" ]
