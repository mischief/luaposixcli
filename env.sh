#!/bin/sh
# SPDX-License-Identifier: ISC
# env.sh - set up environment to use luaposixcli utilities
#
# Usage: . /path/to/luaposixcli/env.sh [prefix]
#
# Default prefix: ~/.luaposixcli
# To install first: meson setup build --prefix ~/.luaposixcli && meson install -C build

_LUAPOSIXCLI_PREFIX="${1:-$HOME/.luaposixcli}"
_LUAPOSIXCLI_LUA="${LUAPOSIXCLI_LUA:-lua5.4}"

# Detect lua version using the system lua (before modifying PATH)
# Use env -i to avoid any shell hooks that might invoke our utilities
_LUAPOSIXCLI_LUAVER="$(env -i PATH="$PATH" "$_LUAPOSIXCLI_LUA" -e 'print(_VERSION:match("%d+%.%d+"))' 2>/dev/null)"
if [ -z "$_LUAPOSIXCLI_LUAVER" ]; then
    echo "env.sh: cannot find $_LUAPOSIXCLI_LUA" >&2
    return 1
fi

# Add lua module paths first (before PATH, so our modules don't interfere)
export LUA_PATH="$_LUAPOSIXCLI_PREFIX/share/lua/$_LUAPOSIXCLI_LUAVER/?.lua;$_LUAPOSIXCLI_PREFIX/share/lua/$_LUAPOSIXCLI_LUAVER/?/init.lua;${LUA_PATH:-;}"
export LUA_CPATH="$_LUAPOSIXCLI_PREFIX/lib/lua/$_LUAPOSIXCLI_LUAVER/?.so;$_LUAPOSIXCLI_PREFIX/lib64/lua/$_LUAPOSIXCLI_LUAVER/?.so;${LUA_CPATH:-;}"

# Prepend bin to PATH last
export PATH="$_LUAPOSIXCLI_PREFIX/bin:$PATH"

unset _LUAPOSIXCLI_PREFIX _LUAPOSIXCLI_LUA _LUAPOSIXCLI_LUAVER
