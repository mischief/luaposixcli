#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
[ "$(lua5.4 "$D/echo.lua" hello world)" = "hello world" ] &&
[ "$(lua5.4 "$D/echo.lua")" = "" ]
