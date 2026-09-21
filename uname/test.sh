#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
[ "$(lua5.4 "$D/uname.lua")" = "$(uname -s)" ] &&
[ "$(lua5.4 "$D/uname.lua" -m)" = "$(uname -m)" ] &&
# the fields, and -a as all of them
[ "$(lua5.4 "$D/uname.lua" -s)" = "$(uname -s)" ] &&
[ "$(lua5.4 "$D/uname.lua" -nr)" = "$(uname -nr)" ] &&
[ "$(lua5.4 "$D/uname.lua" -a)" = "$(uname -srvmn | tr ' ' '\n' | wc -l > /dev/null; uname -s) $(uname -n) $(uname -r) $(uname -v) $(uname -m)" ] &&
! lua5.4 "$D/uname.lua" -Z 2>/dev/null
