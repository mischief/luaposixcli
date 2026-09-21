#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
OUT=$(lua5.4 "$D/id.lua")
echo "$OUT" | grep -q "uid=" && echo "$OUT" | grep -q "gid=" &&
# the selectors, each against what the system id says
[ "$(lua5.4 "$D/id.lua" -u)" = "$(id -u)" ] &&
[ "$(lua5.4 "$D/id.lua" -g)" = "$(id -g)" ] &&
[ "$(lua5.4 "$D/id.lua" -un)" = "$(id -un)" ] &&
[ "$(lua5.4 "$D/id.lua" -G)" = "$(id -G)" ] &&
[ "$(lua5.4 "$D/id.lua" -Gn)" = "$(id -Gn)" ] &&
# -n without one of them, and an unknown option, are usage errors
! lua5.4 "$D/id.lua" -n 2>/dev/null &&
! lua5.4 "$D/id.lua" -Z 2>/dev/null
