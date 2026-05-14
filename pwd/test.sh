#!/bin/sh
# SPDX-License-Identifier: ISC
[ "$(lua5.4 "$(dirname "$0")/pwd.lua")" = "$(pwd)" ]
