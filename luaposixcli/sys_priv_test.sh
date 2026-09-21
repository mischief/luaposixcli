#!/bin/sh
# SPDX-License-Identifier: ISC
# The half of luaposixcli.sys that needs privilege. A user namespace
# hands out most of it, so these calls get run rather than described.
# What a namespace will not give - swapon, init_module, settime, a
# device node - is left out rather than faked.
D="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$D/.." && pwd)"
export LUA_PATH="$ROOT/?.lua;$ROOT/?/init.lua;${LUA_PATH:-;}"
export LUA_CPATH="${LUAPOSIXCLI_BUILD:-$ROOT/build}/?.so;${LUA_CPATH:-;}"

command -v unshare >/dev/null 2>&1 || exit 77
# a kernel that does not hand out user namespaces cannot run any of this
unshare -r -m -u true 2>/dev/null || exit 77

# everything below runs inside a namespace of our own
if [ "$IN_NS" != "1" ]; then
	IN_NS=1 exec unshare -r -m -u "$0" "$@"
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# sethostname, and uname reading it back
lua5.4 -e '
local sys = require("luaposixcli.sys")
local utsname = require("posix.sys.utsname")
assert(sys.sethostname("luaposixcli-test") == 0, "sethostname failed")
assert(utsname.uname().nodename == "luaposixcli-test", "hostname did not take")
' || exit 1

# mount and umount, with a file written through the mount to prove it
lua5.4 -e '
local sys = require("luaposixcli.sys")
local stat = require("posix.sys.stat")
local at = "'"$TMP"'/mp"
assert(stat.mkdir(at))
assert(sys.mount("none", at, "tmpfs", 0, nil) == 0, "mount failed")
local f = assert(io.open(at .. "/file", "w"))
f:write("through the mount"); f:close()
assert(sys.umount(at) == 0, "umount failed")
-- the file was on the tmpfs, so taking the tmpfs away takes it with it
assert(stat.stat(at .. "/file") == nil, "the file outlived its filesystem")

-- the flags have to reach the kernel: a read-only mount refuses a write,
-- and a binding that dropped the argument would look like a working one
assert(sys.mount("none", at, "tmpfs", sys.MS_RDONLY, nil) == 0, "ro mount failed")
local ro = io.open(at .. "/file", "w")
if ro then ro:close() end
assert(ro == nil, "wrote to a read-only mount")
assert(sys.umount(at) == 0)
' || exit 1

# chroot, which moves what "/" means for the rest of the process
mkdir -p "$TMP/jail/inside"
lua5.4 -e '
local sys = require("luaposixcli.sys")
local unistd = require("posix.unistd")
local dirent = require("posix.dirent")
assert(sys.chroot("'"$TMP"'/jail") == 0, "chroot failed")
unistd.chdir("/")
local names = {}
for _, name in ipairs(dirent.dir("/")) do names[name] = true end
assert(names["inside"], "the new root is not the directory we named")
assert(not names["etc"], "the old root is still there")
' || exit 1

# unshare and setns: a uts namespace of its own, then back to this one
lua5.4 -e '
local sys = require("luaposixcli.sys")
local fcntl = require("posix.fcntl")
local unistd = require("posix.unistd")
local utsname = require("posix.sys.utsname")
local here = assert(fcntl.open("/proc/self/ns/uts", fcntl.O_RDONLY))
local before = utsname.uname().nodename
assert(sys.unshare(sys.CLONE_NEWUTS) == 0, "unshare failed")
assert(sys.sethostname("in-the-new-one") == 0)
assert(utsname.uname().nodename == "in-the-new-one")
assert(sys.setns(here, sys.CLONE_NEWUTS) == 0, "setns failed")
assert(utsname.uname().nodename == before,
	"setns did not put us back: " .. utsname.uname().nodename)
unistd.close(here)
' || exit 1

# pivot_root, which is how an initramfs hands the machine over. The new
# root has to be a mount point of its own and the old one a directory
# under it. It moves the root for every process in the namespace, so it
# gets a namespace of its own and the cleanup below still has a /.
unshare -m lua5.4 -e '
local sys = require("luaposixcli.sys")
local unistd = require("posix.unistd")
local stat = require("posix.sys.stat")
local dirent = require("posix.dirent")
local new = "'"$TMP"'/newroot"
assert(stat.mkdir(new))
assert(sys.mount("none", new, "tmpfs", 0, nil) == 0, "mount of the new root failed")
assert(stat.mkdir(new .. "/old"))
assert(stat.mkdir(new .. "/marker"))
-- the mounts this namespace inherited are shared, and pivot_root
-- refuses while they are
assert(sys.mount("none", "/", "none", sys.MS_REC | sys.MS_PRIVATE, nil) == 0,
	"could not make the mounts private")
assert(sys.pivot_root(new, new .. "/old") == 0, "pivot_root failed")
unistd.chdir("/")
local names = {}
for _, name in ipairs(dirent.dir("/")) do names[name] = true end
assert(names["marker"], "/ is not the root we pivoted to")
assert(names["old"], "the old root was not put where we asked")
' || exit 1

exit 0
