#!/bin/sh
# SPDX-License-Identifier: ISC
# Integration tests for POSIX make implementation
set -e
D="$(cd "$(dirname "$0")" && pwd)"
MAKE="lua5.4 $D/make.lua"
PASS=0
FAIL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

pass() { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }

# Test: basic rule execution
cat > "$TMPDIR/Makefile" <<'EOF'
all:
	@echo hello
EOF
OUT=$($MAKE -f "$TMPDIR/Makefile" 2>&1)
[ "$OUT" = "hello" ] && pass || fail "basic rule execution: got '$OUT'"

# Test: variable expansion
cat > "$TMPDIR/Makefile" <<'EOF'
MSG = world
all:
	@echo $(MSG)
EOF
OUT=$($MAKE -f "$TMPDIR/Makefile" 2>&1)
[ "$OUT" = "world" ] && pass || fail "variable expansion: got '$OUT'"

# Test: command-line macro override
cat > "$TMPDIR/Makefile" <<'EOF'
CC = gcc
all:
	@echo $(CC)
EOF
OUT=$($MAKE -f "$TMPDIR/Makefile" CC=clang 2>&1)
[ "$OUT" = "clang" ] && pass || fail "command-line macro: got '$OUT'"

# Test: multiple prerequisites and ordering
cat > "$TMPDIR/Makefile" <<'EOF'
all: a b
	@echo done

a:
	@echo a

b:
	@echo b
EOF
OUT=$($MAKE -f "$TMPDIR/Makefile" 2>&1)
[ "$OUT" = "$(printf 'a\nb\ndone')" ] && pass || fail "prerequisites ordering: got '$OUT'"

# Test: dry-run mode (-n)
cat > "$TMPDIR/Makefile" <<'EOF'
all:
	echo running
EOF
OUT=$($MAKE -n -f "$TMPDIR/Makefile" 2>&1)
[ "$OUT" = "echo running" ] && pass || fail "dry-run: got '$OUT'"

# Test: .PHONY target always rebuilds
cat > "$TMPDIR/Makefile" <<'EOF'
.PHONY: all
all:
	@echo phony
EOF
touch "$TMPDIR/all"
OUT=$($MAKE -f "$TMPDIR/Makefile" 2>&1)
[ "$OUT" = "phony" ] && pass || fail ".PHONY: got '$OUT'"
rm -f "$TMPDIR/all"

# Test: simply-expanded variable (:=)
cat > "$TMPDIR/Makefile" <<'EOF'
A = hello
B := $(A)
A = goodbye
all:
	@echo $(B)
EOF
OUT=$($MAKE -f "$TMPDIR/Makefile" 2>&1)
[ "$OUT" = "hello" ] && pass || fail "simply-expanded :=: got '$OUT'"

# Test: recursive variable
cat > "$TMPDIR/Makefile" <<'EOF'
A = hello
B = $(A)
A = goodbye
all:
	@echo $(B)
EOF
OUT=$($MAKE -f "$TMPDIR/Makefile" 2>&1)
[ "$OUT" = "goodbye" ] && pass || fail "recursive variable: got '$OUT'"

# Test: automatic variable $@
cat > "$TMPDIR/Makefile" <<'EOF'
.PHONY: all
all:
	@echo $@
EOF
OUT=$($MAKE -f "$TMPDIR/Makefile" 2>&1)
[ "$OUT" = "all" ] && pass || fail "automatic \$@: got '$OUT'"

# Test: pattern rule
cat > "$TMPDIR/Makefile" <<'EOF'
all: hello.txt

%.txt:
	@echo making $@
EOF
OUT=$($MAKE -f "$TMPDIR/Makefile" 2>&1)
[ "$OUT" = "making hello.txt" ] && pass || fail "pattern rule: got '$OUT'"

# Test: inference rule (.c.o style)
cat > "$TMPDIR/hello.c" <<'EOF'
int main() { return 0; }
EOF
cat > "$TMPDIR/Makefile" <<'EOF'
.SUFFIXES: .c .o
.c.o:
	@echo compiling $< to $@
all: hello.o
EOF
OUT=$(cd "$TMPDIR" && $MAKE -f Makefile 2>&1)
[ "$OUT" = "compiling hello.c to hello.o" ] && pass || fail "inference rule: got '$OUT'"

# Test: conditional (ifdef)
cat > "$TMPDIR/Makefile" <<'EOF'
FOO = bar
ifdef FOO
MSG = defined
else
MSG = undefined
endif
all:
	@echo $(MSG)
EOF
OUT=$($MAKE -f "$TMPDIR/Makefile" 2>&1)
[ "$OUT" = "defined" ] && pass || fail "ifdef true: got '$OUT'"

# Test: conditional (ifndef)
cat > "$TMPDIR/Makefile" <<'EOF'
ifndef FOO
MSG = undefined
else
MSG = defined
endif
all:
	@echo $(MSG)
EOF
OUT=$($MAKE -f "$TMPDIR/Makefile" 2>&1)
[ "$OUT" = "undefined" ] && pass || fail "ifndef true: got '$OUT'"

# Test: += append
cat > "$TMPDIR/Makefile" <<'EOF'
CFLAGS = -O2
CFLAGS += -Wall
all:
	@echo $(CFLAGS)
EOF
OUT=$($MAKE -f "$TMPDIR/Makefile" 2>&1)
[ "$OUT" = "-O2 -Wall" ] && pass || fail "+= append: got '$OUT'"

# Test: question mode (-q) with up-to-date target
touch "$TMPDIR/src.c"
sleep 1
touch "$TMPDIR/target.o"
cat > "$TMPDIR/Makefile" <<'EOF'
target.o: src.c
	@echo building
EOF
(cd "$TMPDIR" && $MAKE -q -f Makefile target.o >/dev/null 2>&1) && pass || fail "-q up-to-date"

# Test: question mode (-q) with out-of-date target
touch "$TMPDIR/target2.o"
sleep 1
touch "$TMPDIR/src2.c"
cat > "$TMPDIR/Makefile" <<'EOF'
target2.o: src2.c
	@echo building
EOF
(cd "$TMPDIR" && $MAKE -q -f Makefile target2.o >/dev/null 2>&1) && fail "-q out-of-date should fail" || pass

# Test: silent mode (-s)
cat > "$TMPDIR/Makefile" <<'EOF'
all:
	echo visible
EOF
OUT=$($MAKE -s -f "$TMPDIR/Makefile" 2>&1)
# In silent mode, the command itself shouldn't be echoed, only its output
[ "$OUT" = "visible" ] && pass || fail "silent mode: got '$OUT'"

# Test: line continuation
cat > "$TMPDIR/Makefile" <<'EOF'
SRCS = a.c \
       b.c \
       c.c
all:
	@echo $(SRCS)
EOF
OUT=$($MAKE -f "$TMPDIR/Makefile" 2>&1)
[ "$OUT" = "a.c b.c c.c" ] && pass || fail "line continuation: got '$OUT'"

# Test: ignore error prefix (-)
cat > "$TMPDIR/Makefile" <<'EOF'
.PHONY: all
all:
	-false
	@echo ok
EOF
OUT=$($MAKE -f "$TMPDIR/Makefile" 2>&1)
echo "$OUT" | grep -q "ok" && pass || fail "ignore error prefix: got '$OUT'"

# Test: $(@D) and $(@F) automatic variables
cat > "$TMPDIR/Makefile" <<'EOF'
.PHONY: src/foo.o
src/foo.o:
	@echo $(@D) $(@F)
EOF
OUT=$($MAKE -f "$TMPDIR/Makefile" src/foo.o 2>&1)
[ "$OUT" = "src/ foo.o" ] && pass || fail "\$(@D) \$(@F): got '$OUT'"

# Test: pattern substitution $(VAR:%.c=%.o)
cat > "$TMPDIR/Makefile" <<'EOF'
SRCS = foo.c bar.c baz.c
OBJS = $(SRCS:%.c=%.o)
all:
	@echo $(OBJS)
EOF
OUT=$($MAKE -f "$TMPDIR/Makefile" 2>&1)
[ "$OUT" = "foo.o bar.o baz.o" ] && pass || fail "pattern subst: got '$OUT'"

# Test: single-suffix inference rule (.c: builds executable)
cat > "$TMPDIR/hello.c" <<'EOF'
int main() { return 0; }
EOF
cat > "$TMPDIR/Makefile" <<'EOF'
.SUFFIXES: .c
.c:
	@echo building $@ from $<
all: hello
EOF
OUT=$(cd "$TMPDIR" && $MAKE -f Makefile 2>&1)
[ "$OUT" = "building hello from hello.c" ] && pass || fail "single-suffix rule: got '$OUT'"

# Test: -include silently ignores missing files
cat > "$TMPDIR/Makefile" <<'EOF'
-include nonexistent.mk
all:
	@echo works
EOF
OUT=$($MAKE -f "$TMPDIR/Makefile" 2>&1)
[ "$OUT" = "works" ] && pass || fail "-include silent: got '$OUT'"

# Test: multi-line recipe (backslash continuation preserved)
cat > "$TMPDIR/Makefile" <<'EOF'
.PHONY: all
all:
	@for x in a b c; do \
		echo $$x; \
	done
EOF
OUT=$($MAKE -f "$TMPDIR/Makefile" 2>&1)
EXPECT="$(printf 'a\nb\nc')"
[ "$OUT" = "$EXPECT" ] && pass || fail "multi-line recipe: got '$OUT'"

# Test: MAKEFLAGS passed to sub-make
mkdir -p "$TMPDIR/sub"
cat > "$TMPDIR/sub/Makefile" <<'EOF'
all:
	@echo sub
EOF
cat > "$TMPDIR/Makefile" <<'EOF'
all:
	@echo parent
EOF
# Just verify MAKEFLAGS is set when -s is passed
OUT=$(MAKEFLAGS=s $MAKE -f "$TMPDIR/Makefile" 2>&1)
# In silent mode, command not echoed, only output
[ "$OUT" = "parent" ] && pass || fail "MAKEFLAGS from env: got '$OUT'"

# Test: -j2 parallel execution (basic)
cat > "$TMPDIR/Makefile" <<'EOF'
.PHONY: all a b
all: a b
	@echo done

a:
	@echo a

b:
	@echo b
EOF
OUT=$($MAKE -j2 -f "$TMPDIR/Makefile" 2>&1)
echo "$OUT" | grep -q "a" && echo "$OUT" | grep -q "b" && echo "$OUT" | grep -q "done" && pass || fail "-j2 basic: got '$OUT'"

# Test: -j2 respects dependencies (c depends on a)
cat > "$TMPDIR/Makefile" <<'EOF'
.PHONY: all a b c
all: c b

a:
	@echo a

b:
	@echo b

c: a
	@echo c
EOF
OUT=$($MAKE -j2 -f "$TMPDIR/Makefile" 2>&1)
# 'a' must appear before 'c' (dependency ordering)
A_LINE=$(echo "$OUT" | grep -n "^a$" | cut -d: -f1)
C_LINE=$(echo "$OUT" | grep -n "^c$" | cut -d: -f1)
[ -n "$A_LINE" ] && [ -n "$C_LINE" ] && [ "$A_LINE" -lt "$C_LINE" ] && pass || fail "-j2 deps order: got '$OUT'"

# Test: -j4 with many independent targets
cat > "$TMPDIR/Makefile" <<'EOF'
.PHONY: all t1 t2 t3 t4
all: t1 t2 t3 t4

t1:
	@echo t1
t2:
	@echo t2
t3:
	@echo t3
t4:
	@echo t4
EOF
OUT=$($MAKE -j4 -f "$TMPDIR/Makefile" 2>&1)
echo "$OUT" | grep -q "t1" && echo "$OUT" | grep -q "t2" && echo "$OUT" | grep -q "t3" && echo "$OUT" | grep -q "t4" && pass || fail "-j4 many targets: got '$OUT'"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
