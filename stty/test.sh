#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(cd "$(dirname "$0")" && pwd)"
STTY="lua5.4 $D/stty.lua"

# without a terminal it says so rather than guessing
$STTY < /dev/null 2>&1 | grep -q "not a terminal" || exit 1
# a bad mode name is refused
command -v script >/dev/null 2>&1 || exit 77
script -qec "$STTY nosuchmode" /dev/null < /dev/null 2>&1 | grep -q "unknown mode" || exit 1
# on a real terminal it reports, and size answers two numbers
script -qec "$STTY" /dev/null < /dev/null | grep -q "intr = " || exit 1
script -qec "$STTY size" /dev/null < /dev/null | grep -qE '^[0-9]+ [0-9]+' || exit 1
# raw takes and cooked puts back
script -qec "$STTY raw; $STTY -a | grep -q -- -icanon && $STTY cooked && $STTY -a | grep -q 'icanon'" /dev/null < /dev/null || exit 1
exit 0
