#!/bin/sh
# SPDX-License-Identifier: ISC
# run.sh - build, install to temp dir, and launch the lua shell with our utilities on PATH
set -e

SRC="$(cd "$(dirname "$0")" && pwd)"
BUILDDIR=$(mktemp -d)
DESTDIR=$(mktemp -d)

# build and install
meson setup "$BUILDDIR" "$SRC" >/dev/null 2>&1
meson install -C "$BUILDDIR" --destdir "$DESTDIR" >/dev/null 2>&1

# cleanup build dir immediately
rm -rf "$BUILDDIR"

# set PATH so our utilities take precedence
BINDIR="$DESTDIR/usr/local/bin"
export PATH="$BINDIR:$PATH"
export LUA_PATH="$SRC/?.lua;$SRC/?/init.lua;;"

# exec the shell; cleanup on exit
trap 'rm -rf "$DESTDIR"' EXIT
exec lua5.4 "$SRC/sh/sh.lua" "$@"
