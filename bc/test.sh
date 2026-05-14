#!/bin/sh
# SPDX-License-Identifier: ISC
set -e
D="$(cd "$(dirname "$0")" && pwd)"
BC="lua5.4 $D/bc.lua"

check() {
	desc="$1"; input="$2"; expected="$3"
	got=$(printf '%s\n' "$input" | timeout 5 $BC)
	if [ "$got" = "$expected" ]; then :
	else
		echo "FAIL: $desc"
		echo "  expected: $expected"
		echo "  got:      $got"
		exit 1
	fi
}

# Basic arithmetic
check "addition" "2+3" "5"
check "subtraction" "10-3" "7"
check "multiplication" "6*7" "42"
check "division" "scale=0; 10/3" "3"
check "modulus" "10%3" "1"
check "negative" "-5+3" "-2"
check "parentheses" "(2+3)*4" "20"
check "power" "2^10" "1024"

# Large numbers (under 100 digits)
check "2^50" "2^50" "1125899906842624"
check "factorial" "define f(n){auto i,r; r=1; for(i=2;i<=n;i+=1) r=r*i; return(r)}
f(20)" "2432902008176640000"

# Scale/decimals
check "1/3 scale=5" "scale=5; 1/3" "0.33333"
check "decimal add" "1.5+2.3" "3.8"
check "decimal mul" "1.5*2.0" "3.00"

# Variables
check "variable" "x=5; x*2" "10"
check "compound assign" "x=10; x+=5; x" "15"

# Comparisons
check "equal" "3==3" "1"
check "not equal" "3!=4" "1"
check "less" "2<3" "1"
check "greater" "5>3" "1"

# sqrt
check "sqrt(4)" "scale=0; sqrt(4)" "2"
check "sqrt(2)" "scale=6; sqrt(2)" "1.414213"

# Increment
check "post-increment" "x=5; x++" "5"
check "pre-increment" "x=5; ++x" "6"

# Control flow
check "if" 'if (1 > 0) 42' "42"
check "while" 'x=0; while (x < 3) { x += 1 }; x' "3"
check "for" 'for (i=0; i<5; i+=1) i' "$(printf '0\n1\n2\n3\n4')"

# Functions
check "function" 'define g(a,b){return(a+b)}
g(3,4)' "7"
check "recursive" 'define f(n){if(n<=1) return(1); return(n*f(n-1))}
f(6)' "720"

# Strings
check "string" '"hello"' "hello"

# Arrays
check "array" 'a[0]=5; a[1]=10; a[0]+a[1]' "15"

echo "PASS (all tests)"
