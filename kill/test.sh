#!/bin/sh
# SPDX-License-Identifier: ISC
D="$(dirname "$0")"
sleep 10 &
PID=$!
lua5.4 "$D/kill.lua" "$PID"
wait "$PID" 2>/dev/null
[ $? -gt 128 ]
