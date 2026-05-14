#!/bin/sh
# SPDX-License-Identifier: ISC
# mkinitramfs.sh - pack lua shell + utilities + deps into a bootable initramfs cpio
set -e

SRC="$(cd "$(dirname "$0")" && pwd)"
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

mkdir -p "$ROOT"/{bin,lib64,lib/lua/5.4,share/lua/5.4,dev,proc,sys,tmp,etc}

# Build the project
BUILDDIR=$(mktemp -d)
meson setup "$BUILDDIR" "$SRC" >/dev/null 2>&1
meson install -C "$BUILDDIR" --destdir "$ROOT" >/dev/null 2>&1
# Move installed files to root layout
if [ -d "$ROOT/usr/local/bin" ]; then
	cp "$ROOT/usr/local/bin/"* "$ROOT/bin/"
fi
if [ -d "$ROOT/usr/local/lib64/lua/5.4" ]; then
	cp "$ROOT/usr/local/lib64/lua/5.4/"* "$ROOT/lib/lua/5.4/"
fi
if [ -d "$ROOT/usr/local/lib/lua/5.4" ]; then
	cp "$ROOT/usr/local/lib/lua/5.4/"* "$ROOT/lib/lua/5.4/"
fi
rm -rf "$ROOT/usr" "$BUILDDIR"

# Shell modules (sh/*.lua, excluding tests)
mkdir -p "$ROOT/share/lua/5.4/sh"
for f in "$SRC"/sh/*.lua; do
	case "$f" in *_test.lua) continue;; esac
	cp "$f" "$ROOT/share/lua/5.4/sh/"
done

# lua5.4 binary
cp /usr/bin/lua5.4 "$ROOT/bin/"

# Dynamic linker
cp /usr/lib64/ld-linux-x86-64.so.2 "$ROOT/lib64/"

# Collect all shared library deps
collect_libs() {
	ldd "$1" 2>/dev/null | awk '/=>/{print $3}' | grep "^/"
}

# libs for lua5.4
for lib in $(collect_libs /usr/bin/lua5.4); do
	cp -L "$lib" "$ROOT/lib64/"
done

# luaposix .so modules
mkdir -p "$ROOT/lib/lua/5.4/posix/sys"
for f in $(find /usr/lib64/lua/5.4/posix -name '*.so'); do
	rel=${f#/usr/lib64/lua/5.4/}
	cp "$f" "$ROOT/lib/lua/5.4/$rel"
	for lib in $(collect_libs "$f"); do
		cp -nL "$lib" "$ROOT/lib64/" 2>/dev/null || true
	done
done

# lpeg.so
cp -L "$(eval $(luarocks path --lua-version 5.4 2>/dev/null); lua5.4 -e "print(package.searchpath('lpeg', package.cpath))")" "$ROOT/lib/lua/5.4/"

# luaposix .lua modules
cp -r /usr/share/lua/5.4/posix "$ROOT/share/lua/5.4/"

# re.lua (lpeg companion)
RE="$(eval $(luarocks path --lua-version 5.4 2>/dev/null); lua5.4 -e "print(package.searchpath('re', package.path))")"
[ -f "$RE" ] && cp "$RE" "$ROOT/share/lua/5.4/"

# /usr/bin/env wrapper (can't symlink to /bin/env - circular shebang)
mkdir -p "$ROOT/usr/bin"
cat > "$ROOT/usr/bin/env" << 'ENVEOF'
#!/bin/lua5.4
local unistd = require("posix.unistd")
-- skip env options, find command
local i = 1
while arg[i] and arg[i]:sub(1,1) == "-" do i = i + 1 end
if not arg[i] then
  for k, v in pairs(require("posix.stdlib").getenv()) do
    io.write(k .. "=" .. v .. "\n")
  end
  os.exit(0)
end
local cmd = arg[i]
local args = {[0] = cmd}
for j = i + 1, #arg do args[#args+1] = arg[j] end
unistd.execp(cmd, args)
io.stderr:write("env: " .. cmd .. ": No such file or directory\n")
os.exit(127)
ENVEOF
chmod 755 "$ROOT/usr/bin/env"
ln -sf /bin/lua5.4 "$ROOT/usr/bin/lua5.4"

# Remove libswmhack if it snuck in (LD_PRELOAD artifact)
rm -f "$ROOT/lib64/libswmhack"*

# Create /bin/sh wrapper that sets up paths and execs lua shell
cat > "$ROOT/bin/sh" << 'EOF'
#!/bin/lua5.4
package.path = "/share/lua/5.4/?.lua;/share/lua/5.4/?/init.lua"
package.cpath = "/lib/lua/5.4/?.so;/lib/lua/5.4/?/init.so"
arg[0] = "/bin/sh"
dofile("/share/lua/5.4/sh/sh.lua")
EOF
chmod 755 "$ROOT/bin/sh"

# /init (PID 1) - lua script, no shell dependency
cat > "$ROOT/init" << 'EOF'
#!/bin/lua5.4
local ok, err = pcall(function()
  package.path = "/share/lua/5.4/?.lua;/share/lua/5.4/?/init.lua"
  package.cpath = "/lib/lua/5.4/?.so;/lib/lua/5.4/?/init.so"
  local stdlib = require("posix.stdlib")
  local unistd = require("posix.unistd")
  local fcntl = require("posix.fcntl")
  -- ensure fds 0/1/2 all point to /dev/console
  unistd.close(0)
  unistd.close(1)
  unistd.close(2)
  fcntl.open("/dev/console", fcntl.O_RDWR) -- fd 0
  unistd.dup(0) -- fd 1
  unistd.dup(0) -- fd 2
  stdlib.setenv("PATH", "/bin")
  stdlib.setenv("LUA_PATH", "/share/lua/5.4/?.lua;/share/lua/5.4/?/init.lua")
  stdlib.setenv("LUA_CPATH", "/lib/lua/5.4/?.so;/lib/lua/5.4/?/init.so")
  stdlib.setenv("HOME", "/tmp")
  stdlib.setenv("TERM", "linux")
  unistd.write(1, "luaposixcli initramfs\n")
  arg = {[0] = "/bin/sh"}
  dofile("/share/lua/5.4/sh/sh.lua")
end)
if not ok then
  io.stderr:write("INIT ERROR: " .. tostring(err) .. "\n")
  while true do require("posix.unistd").sleep(9999) end
end
EOF
chmod 755 "$ROOT/init"

# /etc/profile - mount filesystems on first shell start
cat > "$ROOT/etc/profile" << 'EOF'
mount -t proc proc /proc 2>/dev/null
mount -t sysfs sys /sys 2>/dev/null
mount -t devtmpfs dev /dev 2>/dev/null
EOF

# /etc/passwd for id(1) etc
echo "root:x:0:0:root:/tmp:/bin/sh" > "$ROOT/etc/passwd"
echo "root:x:0:" > "$ROOT/etc/group"

# Build cpio
OUT="${1:-$SRC/initramfs.cpio.gz}"
(cd "$ROOT" && find . | cpio -o -H newc --quiet | gzip -9) > "$OUT"

echo "initramfs: $OUT ($(du -h "$OUT" | cut -f1))"
