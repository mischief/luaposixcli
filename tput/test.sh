#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(cd "$(dirname "$0")" && pwd)"
TPUT="lua5.4 $D/tput.lua"

# the numbers a script asks for, from the environment on a sizeless line
[ "$(TERM=xterm LINES=48 COLUMNS=132 $TPUT cols)" = "132" ] || exit 1
[ "$(TERM=xterm LINES=48 COLUMNS=132 $TPUT lines)" = "48" ] || exit 1
# strings, compared with the system tput where it is installed
[ "$(TERM=xterm $TPUT sgr0 | od -An -c | tr -d ' \n')" = "033[0m" ] || exit 1
[ "$(TERM=xterm $TPUT cup 2 4 | od -An -c | tr -d ' \n')" = "033[3;5H" ] || exit 1
[ "$(TERM=xterm $TPUT setaf 1 | od -An -c | tr -d ' \n')" = "033[31m" ] || exit 1
# a terminal that cannot take them gets nothing and a failure
TERM=dumb $TPUT bold >/dev/null 2>&1 && exit 1
TERM= $TPUT clear >/dev/null 2>&1 && exit 1
# an unknown capability is an error, and the exit status says which kind
TERM=xterm $TPUT nosuchcap >/dev/null 2>&1 && exit 1
# booleans answer through the exit status
TERM=xterm $TPUT am || exit 1
TERM=xterm $TPUT hs && exit 1
exit 0
