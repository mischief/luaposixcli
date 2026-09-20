#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
ECHO="lua5.4 $D/echo.lua"
[ "$($ECHO hello world)" = "hello world" ] &&
[ "$($ECHO)" = "" ] &&
[ "$($ECHO -n a; $ECHO b)" = "ab" ]
