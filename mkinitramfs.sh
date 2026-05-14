#!/bin/sh
# SPDX-License-Identifier: ISC
# mkinitramfs.sh - build a minimal initramfs with lua + our utilities
set -e

SRC="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SRC/.rootfs"
rm -rf "$ROOT"
mkdir -p "$ROOT"
trap 'rm -rf "$ROOT"' EXIT

MIRROR="${MIRROR:-https://deb.debian.org/debian}"
SUITE="${SUITE:-stable}"

# Packages we need (lua + deps only)
INCLUDE="lua5.4,lua-posix,lua-lpeg,libc-bin"

# Everything from minbase we DON'T need
EXCLUDE="apt,base-files,base-passwd,bash,bsdutils,coreutils,dash,debconf"
EXCLUDE="$EXCLUDE,debian-archive-keyring,debianutils,diffutils,dpkg,findutils"
EXCLUDE="$EXCLUDE,grep,gzip,hostname,init-system-helpers,login,login.defs"
EXCLUDE="$EXCLUDE,mawk,mount,ncurses-bin,openssl-provider-legacy,passwd"
EXCLUDE="$EXCLUDE,perl-base,sed,sqv,sysvinit-utils,tar,tzdata"
EXCLUDE="$EXCLUDE,usr-is-merged,util-linux,libpam-modules,libpam-modules-bin"
EXCLUDE="$EXCLUDE,libpam-runtime,libpam0g,libsystemd0,libudev1"
EXCLUDE="$EXCLUDE,libselinux1,libsemanage-common,libsemanage2,libsepol2"
EXCLUDE="$EXCLUDE,libaudit-common,libaudit1,libseccomp2,libsqlite3-0"
EXCLUDE="$EXCLUDE,libssl3t64,libstdc++6,libdebconfclient0,libdb5.3t64"
EXCLUDE="$EXCLUDE,libgmp10,libhogweed6t64,libnettle8t64,liblastlog2-2"
EXCLUDE="$EXCLUDE,libsmartcols1,ncurses-base,libxxhash0"

echo "Running debootstrap (minimal lua environment)..."
sudo debootstrap \
	--variant=minbase \
	--include="$INCLUDE" \
	--exclude="$EXCLUDE" \
	"$SUITE" "$ROOT" "$MIRROR" || {
		echo "debootstrap failed, falling back to host-based method" >&2
		exec "$SRC/mkinitramfs-host.sh" "$@"
	}

# Strip unnecessary files from the debootstrap result
sudo rm -rf "$ROOT"/usr/share/{doc,man,info,lintian,locale,zoneinfo}
sudo rm -rf "$ROOT"/var/{cache,log,lib/apt,lib/dpkg}
sudo rm -rf "$ROOT"/usr/bin/{dpkg*,apt*,perl*}
sudo rm -rf "$ROOT"/usr/sbin
sudo rm -rf "$ROOT"/etc/apt

# Build our project and install
BUILDDIR=$(mktemp -d)
meson setup "$BUILDDIR" "$SRC" >/dev/null 2>&1
meson install -C "$BUILDDIR" --destdir "$ROOT" >/dev/null 2>&1
rm -rf "$BUILDDIR"

# Shell modules
sudo mkdir -p "$ROOT/usr/local/share/lua/5.4/sh" "$ROOT/usr/local/share/lua/5.4/awk"
sudo cp "$SRC"/sh/*.lua "$ROOT/usr/local/share/lua/5.4/sh/" 2>/dev/null || true
sudo cp "$SRC"/awk/lexer.lua "$SRC"/awk/parser.lua "$SRC"/awk/eval.lua "$ROOT/usr/local/share/lua/5.4/awk/" 2>/dev/null || true

# Create /init
sudo tee "$ROOT/init" > /dev/null << 'EOF'
#!/usr/bin/lua5.4
package.path = "/usr/local/share/lua/5.4/?.lua;/usr/share/lua/5.4/?.lua;/usr/local/share/lua/5.4/?/init.lua;/usr/share/lua/5.4/?/init.lua"
package.cpath = "/usr/local/lib/lua/5.4/?.so;/usr/lib/x86_64-linux-gnu/lua/5.4/?.so;/usr/local/lib/x86_64-linux-gnu/lua/5.4/?.so"
local ok, stdlib = pcall(require, "posix.stdlib")
if ok then
  stdlib.setenv("PATH", "/usr/local/bin:/usr/bin:/bin")
  stdlib.setenv("LUA_PATH", package.path)
  stdlib.setenv("LUA_CPATH", package.cpath)
  stdlib.setenv("HOME", "/tmp")
  stdlib.setenv("TERM", "linux")
end
io.write("luaposixcli initramfs (debootstrap)\n")
io.flush()
arg = {[0] = "/usr/local/bin/sh"}
dofile("/usr/local/share/lua/5.4/sh/sh.lua")
EOF
sudo chmod 755 "$ROOT/init"

# Ensure /dev /proc /sys /tmp exist
sudo mkdir -p "$ROOT"/{dev,proc,sys,tmp,etc}
echo "root:x:0:0:root:/tmp:/bin/sh" | sudo tee "$ROOT/etc/passwd" > /dev/null
echo "root:x:0:" | sudo tee "$ROOT/etc/group" > /dev/null

# Build cpio
OUT="${1:-$SRC/initramfs.cpio.gz}"
(cd "$ROOT" && sudo find . | sudo cpio -o -H newc --quiet | gzip -9) > "$OUT"

echo "initramfs: $OUT ($(du -h "$OUT" | cut -f1))"
