#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
SLEEP="lua5.4 $D/sleep.lua"
$SLEEP 0 &&
# a fraction is a legal sleep, and anything that is not a number is not
$SLEEP 0.1 &&
! $SLEEP abc 2>/dev/null &&
! $SLEEP -Z 2>/dev/null &&
! $SLEEP 2>/dev/null
