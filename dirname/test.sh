#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
[ "$(lua5.4 "$D/dirname.lua" /foo/bar/baz)" = "/foo/bar" ] &&
[ "$(lua5.4 "$D/dirname.lua" baz)" = "." ]
