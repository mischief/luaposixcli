#!/bin/sh
# SPDX-License-Identifier: ISC
set -e
D="$(dirname "$0")"
AWK="lua5.4 $D/awk.lua"
PASS=0
FAIL=0

check() {
	desc="$1"; expected="$2"; got="$3"
	if [ "$got" = "$expected" ]; then
		PASS=$((PASS + 1))
	else
		FAIL=$((FAIL + 1))
		echo "FAIL: $desc"
		echo "  expected: $(printf '%s' "$expected" | head -3)"
		echo "  got:      $(printf '%s' "$got" | head -3)"
	fi
}

# Basic print
out=$(printf 'hello world\n' | $AWK '{ print $1 }')
check "print field" "hello" "$out"

# Field separator
out=$(printf 'a:b:c\n' | $AWK -F: '{ print $2 }')
check "-F option" "b" "$out"

# BEGIN/END
out=$(printf 'x\ny\nz\n' | $AWK 'BEGIN{n=0} {n++} END{print n}')
check "BEGIN/END counter" "3" "$out"

# Arithmetic
out=$(printf '10\n20\n30\n' | $AWK '{s+=$1} END{print s}')
check "sum" "60" "$out"

# NR and NF
out=$(printf 'a b c\nd e\n' | $AWK '{ print NR, NF }')
check "NR NF" "$(printf '1 3\n2 2')" "$out"

# Pattern matching
out=$(printf 'foo\nbar\nbaz\n' | $AWK '/ba/ { print }')
check "regex pattern" "$(printf 'bar\nbaz')" "$out"

# If/else
out=$(printf '1\n2\n3\n4\n5\n' | $AWK '{ if ($1 % 2 == 0) print $1, "even"; else print $1, "odd" }')
check "if/else" "$(printf '1 odd\n2 even\n3 odd\n4 even\n5 odd')" "$out"

# For loop
out=$(printf 'a b c d\n' | $AWK '{ for (i=NF; i>=1; i--) printf "%s ", $i; printf "\n" }')
check "for loop reverse" "d c b a " "$(printf '%s' "$out" | tr -d '\n'| sed 's/$//')"

# Arrays and for-in
out=$(printf 'a\nb\na\nc\nb\na\n' | $AWK '{ c[$1]++ } END { for (k in c) print k, c[k] }' | sort)
check "array counting" "$(printf 'a 3\nb 2\nc 1')" "$out"

# User-defined function
out=$(printf '3 7\n10 2\n' | $AWK '
function max(a, b) { if (a > b) return a; return b }
{ print max($1, $2) }')
check "user function" "$(printf '7\n10')" "$out"

# String functions
out=$(printf 'Hello World\n' | $AWK '{ print length($0), toupper($1), tolower($2) }')
check "string funcs" "11 HELLO world" "$out"

# substr
out=$(printf 'abcdef\n' | $AWK '{ print substr($0, 2, 3) }')
check "substr" "bcd" "$out"

# sub/gsub
out=$(printf 'hello world hello\n' | $AWK '{ sub(/hello/, "hi"); print }')
check "sub" "hi world hello" "$out"

out=$(printf 'hello world hello\n' | $AWK '{ gsub(/hello/, "hi"); print }')
check "gsub" "hi world hi" "$out"

# split
out=$(printf 'a:b:c:d\n' | $AWK '{ n = split($0, arr, ":"); for (i=1; i<=n; i++) print arr[i] }')
check "split" "$(printf 'a\nb\nc\nd')" "$out"

# printf
out=$(printf 'x\n' | $AWK '{ printf "%05d %s\n", 42, "hi" }')
check "printf" "00042 hi" "$out"

# Concatenation
out=$(printf 'x\n' | $AWK '{ print "a" "b" "c" }')
check "concat" "abc" "$out"

# Ternary
out=$(printf '1\n0\n' | $AWK '{ print ($1 ? "yes" : "no") }')
check "ternary" "$(printf 'yes\nno')" "$out"

# Assignment operators
out=$(printf 'x\n' | $AWK 'BEGIN{ x=10; x+=5; x*=2; print x }')
check "compound assign" "30" "$out"

# match()
out=$(printf 'hello world\n' | $AWK '{ print match($0, /wor/), RSTART, RLENGTH }')
check "match" "7 7 3" "$out"

# index()
out=$(printf 'hello world\n' | $AWK '{ print index($0, "world") }')
check "index" "7" "$out"

# sprintf
out=$(printf 'x\n' | $AWK '{ print sprintf("[%05.1f]", 3.14) }')
check "sprintf" "[003.1]" "$out"

# Multiple rules
out=$(printf '1\n2\n3\n' | $AWK '$1==1{print "one"} $1==2{print "two"} $1==3{print "three"}')
check "multi-rule" "$(printf 'one\ntwo\nthree')" "$out"

# Range pattern
out=$(printf 'a\nSTART\nb\nc\nSTOP\nd\n' | $AWK '/START/,/STOP/ { print }')
check "range pattern" "$(printf 'START\nb\nc\nSTOP')" "$out"

# next statement
out=$(printf '1\n2\n3\n4\n5\n' | $AWK '{ if ($1 == 3) next; print }')
check "next" "$(printf '1\n2\n4\n5')" "$out"

# OFS
out=$(printf 'a b c\n' | $AWK 'BEGIN{OFS=","} { $1=$1; print }')
check "OFS" "a,b,c" "$out"

# Field assignment
out=$(printf 'a b c\n' | $AWK '{ $2 = "X"; print }')
check "field assign" "a X c" "$out"

# do-while
out=$(printf 'x\n' | $AWK '{ i=1; do { printf "%d ", i; i++ } while (i <= 3); printf "\n" }')
check "do-while" "1 2 3 " "$(printf '%s' "$out" | tr -d '\n')"

# delete
out=$(printf 'x\n' | $AWK '{ a[1]="x"; a[2]="y"; delete a[1]; for (k in a) print k, a[k] }')
check "delete" "2 y" "$out"

# int()
out=$(printf 'x\n' | $AWK '{ print int(3.9), int(-3.9) }')
check "int" "3 -3" "$out"

# NF assignment
out=$(printf 'a b c d e\n' | $AWK '{ NF=3; print }')
check "NF assign" "a b c" "$out"

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
