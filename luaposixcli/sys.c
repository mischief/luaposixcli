/*
 * SPDX-License-Identifier: ISC
 * notposix.c - Lua 5.4 module exposing POSIX functions not in luaposix
 */
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/resource.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <grp.h>
#include <sys/file.h>
#include <sys/sysmacros.h>
#include <sys/stat.h>
#include <limits.h>
#include <pwd.h>
#ifdef __linux__
#include <shadow.h>
#include <sys/syscall.h>
#endif
#include <regex.h>
#include <time.h>

#include <lua.h>
#include <lauxlib.h>

/* notposix.environ() -> table of "KEY=VALUE" strings */
static int
l_environ(lua_State *L)
{
	extern char **environ;
	lua_newtable(L);
	int i = 1;
	for (char **ep = environ; *ep != NULL; ep++) {
		lua_pushstring(L, *ep);
		lua_rawseti(L, -2, i++);
	}
	return 1;
}

/* notposix.getpriority(which, who) -> priority or nil, errmsg */
static int
l_getpriority(lua_State *L)
{
	int which = luaL_checkinteger(L, 1);
	int who = luaL_checkinteger(L, 2);

	errno = 0;
	int prio = getpriority(which, who);
	if (prio == -1 && errno != 0) {
		lua_pushnil(L);
		lua_pushstring(L, strerror(errno));
		return 2;
	}
	lua_pushinteger(L, prio);
	return 1;
}

/* notposix.setpriority(which, who, prio) -> 0 or nil, errmsg */
static int
l_setpriority(lua_State *L)
{
	int which = luaL_checkinteger(L, 1);
	int who = luaL_checkinteger(L, 2);
	int prio = luaL_checkinteger(L, 3);

	if (setpriority(which, who, prio) == -1) {
		lua_pushnil(L);
		lua_pushstring(L, strerror(errno));
		return 2;
	}
	lua_pushinteger(L, 0);
	return 1;
}

#define REGEX_MT "posix_regex"

/* notposix.regcomp(pattern, flags) -> regex userdata or nil, errmsg */
static int
l_regcomp(lua_State *L)
{
	const char *pattern = luaL_checkstring(L, 1);
	int flags = luaL_optinteger(L, 2, 0);

	regex_t *re = lua_newuserdata(L, sizeof(regex_t));
	luaL_setmetatable(L, REGEX_MT);

	int rc = regcomp(re, pattern, flags);
	if (rc != 0) {
		char errbuf[256];
		regerror(rc, re, errbuf, sizeof(errbuf));
		lua_pushnil(L);
		lua_pushstring(L, errbuf);
		return 2;
	}
	return 1;
}

/* regex:exec(string) -> true/false, or match offsets */
static int
l_regexec(lua_State *L)
{
	regex_t *re = luaL_checkudata(L, 1, REGEX_MT);
	const char *str = luaL_checkstring(L, 2);

	regmatch_t pmatch[10];
	int rc = regexec(re, str, 10, pmatch, 0);
	if (rc == REG_NOMATCH) {
		lua_pushboolean(L, 0);
		return 1;
	}
	if (rc != 0) {
		lua_pushboolean(L, 0);
		return 1;
	}
	/* return match offsets as a table of {so, eo} pairs (1-indexed) */
	lua_newtable(L);
	for (int i = 0; i < 10 && pmatch[i].rm_so != -1; i++) {
		lua_newtable(L);
		lua_pushinteger(L, pmatch[i].rm_so + 1);
		lua_rawseti(L, -2, 1);
		lua_pushinteger(L, pmatch[i].rm_eo);
		lua_rawseti(L, -2, 2);
		lua_rawseti(L, -2, i + 1);
	}
	return 1;
}

/* regex:__gc */
static int
l_regfree(lua_State *L)
{
	regex_t *re = luaL_checkudata(L, 1, REGEX_MT);
	regfree(re);
	return 0;
}

/* notposix.regmatch(pattern, string, flags) -> bool (convenience) */
static int
l_regmatch(lua_State *L)
{
	const char *pattern = luaL_checkstring(L, 1);
	const char *str = luaL_checkstring(L, 2);
	int flags = luaL_optinteger(L, 3, 0);

	regex_t re;
	int rc = regcomp(&re, pattern, flags);
	if (rc != 0) {
		lua_pushboolean(L, 0);
		regfree(&re);
		return 1;
	}
	rc = regexec(&re, str, 0, NULL, 0);
	lua_pushboolean(L, rc == 0);
	regfree(&re);
	return 1;
}

static const luaL_Reg regex_methods[] = {
	{"exec", l_regexec},
	{"__gc", l_regfree},
	{NULL, NULL}
};

/* notposix.mount(source, target, fstype[, flags[, data]]) -> 0 or nil, errmsg */
static int
l_mount(lua_State *L)
{
#ifdef __linux__
	const char *source = luaL_checkstring(L, 1);
	const char *target = luaL_checkstring(L, 2);
	const char *fstype = luaL_checkstring(L, 3);
	unsigned long flags = luaL_optinteger(L, 4, 0);
	const char *data = luaL_optstring(L, 5, NULL);

	if (mount(source, target, fstype, flags, data) == -1) {
#else
	const char *fstype = luaL_checkstring(L, 1);
	const char *target = luaL_checkstring(L, 2);
	int flags = luaL_optinteger(L, 3, 0);
	const char *data = luaL_optstring(L, 4, NULL);

	if (mount(fstype, target, flags, (void *)data) == -1) {
#endif
		lua_pushnil(L);
		lua_pushstring(L, strerror(errno));
		return 2;
	}
	lua_pushinteger(L, 0);
	return 1;
}

/* notposix.umount(target) -> 0 or nil, errmsg */
static int
l_umount(lua_State *L)
{
	const char *target = luaL_checkstring(L, 1);

#ifdef __linux__
	if (umount(target) == -1) {
#else
	if (unmount(target, 0) == -1) {
#endif
		lua_pushnil(L);
		lua_pushstring(L, strerror(errno));
		return 2;
	}
	lua_pushinteger(L, 0);
	return 1;
}

/* notposix.setpgid(pid, pgid) -> 0 or nil, errmsg */
static int
l_setpgid(lua_State *L)
{
	pid_t pid = luaL_checkinteger(L, 1);
	pid_t pgid = luaL_checkinteger(L, 2);

	if (setpgid(pid, pgid) == -1) {
		lua_pushnil(L);
		lua_pushstring(L, strerror(errno));
		return 2;
	}
	lua_pushinteger(L, 0);
	return 1;
}

/* notposix.winsize([fd]) -> cols, rows or nil, errmsg */
static int
l_winsize(lua_State *L)
{
	int fd = luaL_optinteger(L, 1, 1);
	struct winsize ws;
	if (ioctl(fd, TIOCGWINSZ, &ws) == -1) {
		lua_pushnil(L);
		lua_pushstring(L, strerror(errno));
		return 2;
	}
	lua_pushinteger(L, ws.ws_col);
	lua_pushinteger(L, ws.ws_row);
	return 2;
}

/* notposix.reboot(how) -> restart, halt or power off the machine */
static int
l_reboot(lua_State *L)
{
	int how = (int)luaL_checkinteger(L, 1);

	sync();
	if (reboot(how) == -1) {
		lua_pushnil(L);
		lua_pushstring(L, strerror(errno));
		return 2;
	}
	lua_pushinteger(L, 0);
	return 1;
}

/* notposix.getspnam(name) -> the shadow entry, where there is one.
 * POSIX has nothing to say about shadow passwords, so luaposix has no
 * binding for this and login has nowhere else to get the hash.
 */
static int
l_getspnam(lua_State *L)
{
#ifdef __linux__
	const char *name = luaL_checkstring(L, 1);
	struct spwd *sp = getspnam(name);

	if (sp == NULL) {
		lua_pushnil(L);
		lua_pushstring(L, errno ? strerror(errno) : "no such user");
		return 2;
	}
	lua_newtable(L);
	lua_pushstring(L, sp->sp_namp);  lua_setfield(L, -2, "sp_namp");
	lua_pushstring(L, sp->sp_pwdp ? sp->sp_pwdp : "");
	lua_setfield(L, -2, "sp_pwdp");
	lua_pushinteger(L, sp->sp_lstchg); lua_setfield(L, -2, "sp_lstchg");
	lua_pushinteger(L, sp->sp_min);    lua_setfield(L, -2, "sp_min");
	lua_pushinteger(L, sp->sp_max);    lua_setfield(L, -2, "sp_max");
	lua_pushinteger(L, sp->sp_expire); lua_setfield(L, -2, "sp_expire");
	return 1;
#else
	lua_pushnil(L);
	lua_pushstring(L, "no shadow file on this system");
	return 2;
#endif
}

/* notposix.initgroups(user, gid) -- the supplementary groups that go with
 * an account. Dropping privilege without this leaves the new user in the
 * groups the old one had.
 */
static int
l_initgroups(lua_State *L)
{
	const char *user = luaL_checkstring(L, 1);
	gid_t gid = (gid_t)luaL_checkinteger(L, 2);

	if (initgroups(user, gid) == -1) {
		lua_pushnil(L);
		lua_pushstring(L, strerror(errno));
		return 2;
	}
	lua_pushinteger(L, 0);
	return 1;
}

/* notposix.setgroups(list) -- the supplementary groups, given outright */
static int
l_setgroups(lua_State *L)
{
	gid_t list[NGROUPS_MAX];
	int n = 0;

	luaL_checktype(L, 1, LUA_TTABLE);
	lua_pushnil(L);
	while (lua_next(L, 1) != 0) {
		if (n >= NGROUPS_MAX) {
			lua_pop(L, 2);
			lua_pushnil(L);
			lua_pushstring(L, "too many groups");
			return 2;
		}
		list[n++] = (gid_t)lua_tointeger(L, -1);
		lua_pop(L, 1);
	}
	if (setgroups((size_t)n, list) == -1) {
		lua_pushnil(L);
		lua_pushstring(L, strerror(errno));
		return 2;
	}
	lua_pushinteger(L, 0);
	return 1;
}

/* Kernel modules. The three calls have no libc wrappers on Linux, so
 * they go through syscall(2) directly; nothing else offers them.
 */
static int
l_finit_module(lua_State *L)
{
#if defined(__linux__) && defined(SYS_finit_module)
	int fd = (int)luaL_checkinteger(L, 1);
	const char *params = luaL_optstring(L, 2, "");
	int flags = (int)luaL_optinteger(L, 3, 0);

	if (syscall(SYS_finit_module, fd, params, flags) != 0) {
		lua_pushnil(L);
		lua_pushstring(L, strerror(errno));
		return 2;
	}
	lua_pushinteger(L, 0);
	return 1;
#else
	lua_pushnil(L);
	lua_pushstring(L, "no kernel modules on this system");
	return 2;
#endif
}

static int
l_init_module(lua_State *L)
{
#if defined(__linux__) && defined(SYS_init_module)
	size_t len = 0;
	const char *image = luaL_checklstring(L, 1, &len);
	const char *params = luaL_optstring(L, 2, "");

	if (syscall(SYS_init_module, image, (unsigned long)len, params) != 0) {
		lua_pushnil(L);
		lua_pushstring(L, strerror(errno));
		return 2;
	}
	lua_pushinteger(L, 0);
	return 1;
#else
	lua_pushnil(L);
	lua_pushstring(L, "no kernel modules on this system");
	return 2;
#endif
}

static int
l_delete_module(lua_State *L)
{
#if defined(__linux__) && defined(SYS_delete_module)
	const char *name = luaL_checkstring(L, 1);
	int flags = (int)luaL_optinteger(L, 2, 0);

	if (syscall(SYS_delete_module, name, flags) != 0) {
		lua_pushnil(L);
		lua_pushstring(L, strerror(errno));
		return 2;
	}
	lua_pushinteger(L, 0);
	return 1;
#else
	lua_pushnil(L);
	lua_pushstring(L, "no kernel modules on this system");
	return 2;
#endif
}

/* notposix.sethostname(name) -- privileged, so POSIX does not have it */
static int
l_sethostname(lua_State *L)
{
	size_t len = 0;
	const char *name = luaL_checklstring(L, 1, &len);

	if (sethostname(name, len) == -1) {
		lua_pushnil(L);
		lua_pushstring(L, strerror(errno));
		return 2;
	}
	lua_pushinteger(L, 0);
	return 1;
}

/* notposix.mknod(path, mode, major, minor) -- a device node. Making one
 * is privileged, and luaposix has only mkfifo.
 */
static int
l_mknod(lua_State *L)
{
	const char *path = luaL_checkstring(L, 1);
	mode_t mode = (mode_t)luaL_checkinteger(L, 2);
	unsigned int major = (unsigned int)luaL_optinteger(L, 3, 0);
	unsigned int minor = (unsigned int)luaL_optinteger(L, 4, 0);

	if (mknod(path, mode, makedev(major, minor)) == -1) {
		lua_pushnil(L);
		lua_pushstring(L, strerror(errno));
		return 2;
	}
	lua_pushinteger(L, 0);
	return 1;
}

/* notposix.major(dev), notposix.minor(dev) -- the two halves of the
 * device number a stat gives back
 */
static int
l_major(lua_State *L)
{
	lua_pushinteger(L, (lua_Integer)major((dev_t)luaL_checkinteger(L, 1)));
	return 1;
}

static int
l_minor(lua_State *L)
{
	lua_pushinteger(L, (lua_Integer)minor((dev_t)luaL_checkinteger(L, 1)));
	return 1;
}

/* notposix.ioctlbuf(fd, request, size or string) -> string or nil, errmsg
 * The requests that pass a struct rather than a number. A number asks
 * for a buffer of that many zero bytes; a string is passed as it is.
 * What comes back is the buffer as the kernel left it.
 */
static int
l_ioctlbuf(lua_State *L)
{
	int fd = (int)luaL_checkinteger(L, 1);
	unsigned long request = (unsigned long)luaL_checkinteger(L, 2);
	size_t len = 0;
	const char *in = NULL;
	char *buf;
	int rc;

	if (lua_isnumber(L, 3)) {
		len = (size_t)lua_tointeger(L, 3);
	} else {
		in = luaL_checklstring(L, 3, &len);
	}
	if (len == 0 || len > 65536)
		return luaL_error(L, "ioctlbuf: bad buffer size");

	buf = calloc(1, len);
	if (buf == NULL)
		return luaL_error(L, "ioctlbuf: out of memory");
	if (in != NULL)
		memcpy(buf, in, len);

	rc = ioctl(fd, request, buf);
	if (rc == -1) {
		int saved = errno;
		free(buf);
		lua_pushnil(L);
		lua_pushstring(L, strerror(saved));
		return 2;
	}
	lua_pushlstring(L, buf, len);
	free(buf);
	return 1;
}

/* notposix.settime(seconds[, nanoseconds]) -- set the system clock.
 * POSIX has clock_settime but luaposix binds only the reading half, and
 * setting it is privileged either way.
 */
static int
l_settime(lua_State *L)
{
	struct timespec ts;

	ts.tv_sec = (time_t)luaL_checkinteger(L, 1);
	ts.tv_nsec = (long)luaL_optinteger(L, 2, 0);

	if (clock_settime(CLOCK_REALTIME, &ts) == -1) {
		lua_pushnil(L);
		lua_pushstring(L, strerror(errno));
		return 2;
	}
	lua_pushinteger(L, 0);
	return 1;
}

/* notposix.chroot(path) */
static int
l_chroot(lua_State *L)
{
	const char *path = luaL_checkstring(L, 1);

	if (chroot(path) == -1) {
		lua_pushnil(L);
		lua_pushstring(L, strerror(errno));
		return 2;
	}
	lua_pushinteger(L, 0);
	return 1;
}

/* notposix.pivot_root(new, put_old) -- what an initramfs does to hand
 * the machine over to the real root. No libc wrapper on Linux.
 */
static int
l_pivot_root(lua_State *L)
{
#if defined(__linux__) && defined(SYS_pivot_root)
	const char *new_root = luaL_checkstring(L, 1);
	const char *put_old = luaL_checkstring(L, 2);

	if (syscall(SYS_pivot_root, new_root, put_old) != 0) {
		lua_pushnil(L);
		lua_pushstring(L, strerror(errno));
		return 2;
	}
	lua_pushinteger(L, 0);
	return 1;
#else
	lua_pushnil(L);
	lua_pushstring(L, "pivot_root is a Linux call");
	return 2;
#endif
}

/* notposix.swapon(path, flags) and swapoff(path) */
static int
l_swapon(lua_State *L)
{
#if defined(__linux__) && defined(SYS_swapon)
	const char *path = luaL_checkstring(L, 1);
	int flags = (int)luaL_optinteger(L, 2, 0);

	if (syscall(SYS_swapon, path, flags) != 0) {
		lua_pushnil(L);
		lua_pushstring(L, strerror(errno));
		return 2;
	}
	lua_pushinteger(L, 0);
	return 1;
#else
	lua_pushnil(L);
	lua_pushstring(L, "swap is a Linux call here");
	return 2;
#endif
}

static int
l_swapoff(lua_State *L)
{
#if defined(__linux__) && defined(SYS_swapoff)
	const char *path = luaL_checkstring(L, 1);

	if (syscall(SYS_swapoff, path) != 0) {
		lua_pushnil(L);
		lua_pushstring(L, strerror(errno));
		return 2;
	}
	lua_pushinteger(L, 0);
	return 1;
#else
	lua_pushnil(L);
	lua_pushstring(L, "swap is a Linux call here");
	return 2;
#endif
}

/* notposix.flock(fd, operation) -- a whole-file lock, which POSIX has
 * only as a record lock through fcntl.
 */
static int
l_flock(lua_State *L)
{
	int fd = (int)luaL_checkinteger(L, 1);
	int op = (int)luaL_checkinteger(L, 2);

	if (flock(fd, op) == -1) {
		lua_pushnil(L);
		lua_pushstring(L, strerror(errno));
		return 2;
	}
	lua_pushinteger(L, 0);
	return 1;
}

/* notposix.ioctl(fd, request, arg) -- the integer form, which is what
 * the loop device and the terminal size want.
 */
static int
l_ioctl(lua_State *L)
{
	int fd = (int)luaL_checkinteger(L, 1);
	unsigned long request = (unsigned long)luaL_checkinteger(L, 2);
	long value = (long)luaL_optinteger(L, 3, 0);

	if (ioctl(fd, request, value) == -1) {
		lua_pushnil(L);
		lua_pushstring(L, strerror(errno));
		return 2;
	}
	lua_pushinteger(L, 0);
	return 1;
}

/* notposix.unshare(flags) and setns(fd, type) -- namespaces, which are
 * Linux's and so nobody else's business.
 */
static int
l_unshare(lua_State *L)
{
#if defined(__linux__) && defined(SYS_unshare)
	int flags = (int)luaL_checkinteger(L, 1);

	if (syscall(SYS_unshare, flags) != 0) {
		lua_pushnil(L);
		lua_pushstring(L, strerror(errno));
		return 2;
	}
	lua_pushinteger(L, 0);
	return 1;
#else
	lua_pushnil(L);
	lua_pushstring(L, "namespaces are a Linux thing");
	return 2;
#endif
}

static int
l_setns(lua_State *L)
{
#if defined(__linux__) && defined(SYS_setns)
	int fd = (int)luaL_checkinteger(L, 1);
	int kind = (int)luaL_optinteger(L, 2, 0);

	if (syscall(SYS_setns, fd, kind) != 0) {
		lua_pushnil(L);
		lua_pushstring(L, strerror(errno));
		return 2;
	}
	lua_pushinteger(L, 0);
	return 1;
#else
	lua_pushnil(L);
	lua_pushstring(L, "namespaces are a Linux thing");
	return 2;
#endif
}

static const luaL_Reg notposix_funcs[] = {
	{"getpriority", l_getpriority},
	{"setpriority", l_setpriority},
	{"setpgid", l_setpgid},
	{"winsize", l_winsize},
	{"regcomp", l_regcomp},
	{"regmatch", l_regmatch},
	{"environ", l_environ},
	{"mount", l_mount},
	{"umount", l_umount},
	{"reboot", l_reboot},
	{"getspnam", l_getspnam},
	{"initgroups", l_initgroups},
	{"setgroups", l_setgroups},
	{"init_module", l_init_module},
	{"finit_module", l_finit_module},
	{"delete_module", l_delete_module},
	{"sethostname", l_sethostname},
	{"chroot", l_chroot},
	{"mknod", l_mknod},
	{"major", l_major},
	{"minor", l_minor},
	{"ioctlbuf", l_ioctlbuf},
	{"settime", l_settime},
	{"pivot_root", l_pivot_root},
	{"swapon", l_swapon},
	{"swapoff", l_swapoff},
	{"flock", l_flock},
	{"ioctl", l_ioctl},
	{"unshare", l_unshare},
	{"setns", l_setns},
	{NULL, NULL}
};

int
luaopen_luaposixcli_sys(lua_State *L)
{
	/* create regex metatable */
	luaL_newmetatable(L, REGEX_MT);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	luaL_setfuncs(L, regex_methods, 0);
	lua_pop(L, 1);

	luaL_newlib(L, notposix_funcs);
	/* priority constants */
	lua_pushinteger(L, PRIO_PROCESS); lua_setfield(L, -2, "PRIO_PROCESS");
	lua_pushinteger(L, PRIO_PGRP);    lua_setfield(L, -2, "PRIO_PGRP");
	lua_pushinteger(L, PRIO_USER);    lua_setfield(L, -2, "PRIO_USER");
	/* regex constants */
	lua_pushinteger(L, REG_EXTENDED); lua_setfield(L, -2, "REG_EXTENDED");
	lua_pushinteger(L, REG_ICASE);    lua_setfield(L, -2, "REG_ICASE");
	lua_pushinteger(L, REG_NOSUB);    lua_setfield(L, -2, "REG_NOSUB");
	lua_pushinteger(L, REG_NEWLINE);  lua_setfield(L, -2, "REG_NEWLINE");
	/* mount flags and reboot commands, whatever this system calls them */
#ifdef MS_RDONLY
	lua_pushinteger(L, MS_RDONLY);   lua_setfield(L, -2, "MS_RDONLY");
	lua_pushinteger(L, MS_NOSUID);   lua_setfield(L, -2, "MS_NOSUID");
	lua_pushinteger(L, MS_NODEV);    lua_setfield(L, -2, "MS_NODEV");
	lua_pushinteger(L, MS_NOEXEC);   lua_setfield(L, -2, "MS_NOEXEC");
	lua_pushinteger(L, MS_REMOUNT);  lua_setfield(L, -2, "MS_REMOUNT");
	lua_pushinteger(L, MS_NOATIME);  lua_setfield(L, -2, "MS_NOATIME");
	lua_pushinteger(L, MS_BIND);     lua_setfield(L, -2, "MS_BIND");
#endif
#ifdef __linux__
	/* the namespace flags from sched.h, spelled out so a kernel header
	 * that is not installed does not take unshare with it */
	lua_pushinteger(L, 0x00020000); lua_setfield(L, -2, "CLONE_NEWNS");
	lua_pushinteger(L, 0x04000000); lua_setfield(L, -2, "CLONE_NEWUTS");
	lua_pushinteger(L, 0x08000000); lua_setfield(L, -2, "CLONE_NEWIPC");
	lua_pushinteger(L, 0x10000000); lua_setfield(L, -2, "CLONE_NEWUSER");
	lua_pushinteger(L, 0x20000000); lua_setfield(L, -2, "CLONE_NEWPID");
	lua_pushinteger(L, 0x40000000); lua_setfield(L, -2, "CLONE_NEWNET");
	lua_pushinteger(L, 0x02000000); lua_setfield(L, -2, "CLONE_NEWCGROUP");
#endif
	lua_pushinteger(L, LOCK_SH); lua_setfield(L, -2, "LOCK_SH");
	lua_pushinteger(L, LOCK_EX); lua_setfield(L, -2, "LOCK_EX");
	lua_pushinteger(L, LOCK_UN); lua_setfield(L, -2, "LOCK_UN");
	lua_pushinteger(L, LOCK_NB); lua_setfield(L, -2, "LOCK_NB");
#ifdef __linux__
	/* the real time clock, from linux/rtc.h: read and set the nine
	 * ints of a struct rtc_time */
	lua_pushinteger(L, 0x80247009); lua_setfield(L, -2, "RTC_RD_TIME");
	lua_pushinteger(L, 0x4024700a); lua_setfield(L, -2, "RTC_SET_TIME");
#endif
#ifdef __linux__
	/* the loop device, from linux/loop.h, which is not always installed */
	lua_pushinteger(L, 0x4C00); lua_setfield(L, -2, "LOOP_SET_FD");
	lua_pushinteger(L, 0x4C01); lua_setfield(L, -2, "LOOP_CLR_FD");
	lua_pushinteger(L, 0x4C80); lua_setfield(L, -2, "LOOP_CTL_GET_FREE");
#endif
#ifdef RB_AUTOBOOT
	lua_pushinteger(L, RB_AUTOBOOT); lua_setfield(L, -2, "RB_AUTOBOOT");
#endif
#ifdef RB_HALT_SYSTEM
	lua_pushinteger(L, RB_HALT_SYSTEM); lua_setfield(L, -2, "RB_HALT");
#elif defined(RB_HALT)
	lua_pushinteger(L, RB_HALT);     lua_setfield(L, -2, "RB_HALT");
#endif
#ifdef RB_POWER_OFF
	lua_pushinteger(L, RB_POWER_OFF); lua_setfield(L, -2, "RB_POWEROFF");
#elif defined(RB_POWEROFF)
	lua_pushinteger(L, RB_POWEROFF); lua_setfield(L, -2, "RB_POWEROFF");
#endif
	return 1;
}
