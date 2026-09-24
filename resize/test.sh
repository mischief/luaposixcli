#!/bin/sh
# SPDX-License-Identifier: ISC
# script gives a pty; the answer to the cursor query is fed to it on
# stdin, the way a terminal would send it. stty size then reports what
# the kernel holds, which is the point of the program.
D="$(cd "$(dirname "$0")" && pwd)"
R="lua5.4 $D/resize.lua"
S="lua5.4 $D/../stty/stty.lua"
command -v script >/dev/null 2>&1 || exit 77

out=$(printf '\033[40;100R' | script -qec "$R; $S size" /dev/null 2>&1)
echo "$out" | grep -q "LINES=40; COLUMNS=100; export LINES COLUMNS" || {
	echo "the query path said: $out"; exit 1; }
echo "$out" | grep -q "^40 100" || { echo "the kernel holds: $out"; exit 1; }

# -s asks nothing and sets what it is given
out=$(script -qec "$R -s 24 80; $S size" /dev/null < /dev/null 2>&1)
echo "$out" | grep -q "^24 80" || { echo "-s left: $out"; exit 1; }

# a terminal that answers nothing is an error rather than a guess
out=$(script -qec "$R" /dev/null < /dev/null 2>&1)
echo "$out" | grep -q "did not answer" || { echo "silence gave: $out"; exit 1; }

# the csh spelling
out=$(printf '\033[30;90R' | script -qec "$R -c" /dev/null 2>&1)
echo "$out" | grep -q "setenv COLUMNS 90" || { echo "csh form: $out"; exit 1; }
exit 0
