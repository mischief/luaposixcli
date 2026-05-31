/*
 * SPDX-License-Identifier: ISC
 * notposix.c - Lua 5.4 module exposing POSIX functions not in luaposix
 */
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/resource.h>
#include <sys/mount.h>
#include <regex.h>

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

static const luaL_Reg notposix_funcs[] = {
	{"getpriority", l_getpriority},
	{"setpriority", l_setpriority},
	{"setpgid", l_setpgid},
	{"regcomp", l_regcomp},
	{"regmatch", l_regmatch},
	{"environ", l_environ},
	{"mount", l_mount},
	{"umount", l_umount},
	{NULL, NULL}
};

int
luaopen_notposix(lua_State *L)
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
	return 1;
}
