/*
 * SPDX-License-Identifier: ISC
 * ps/sys.c - portable process listing for Lua
 *
 * Returns a table of {pid, ppid, uid, comm, state, tty} per process.
 * Linux: reads /proc. OpenBSD/FreeBSD: uses kvm_getprocs.
 */

#ifdef __linux__

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <lua.h>
#include <lauxlib.h>

static int l_getprocs(lua_State *L) {
	DIR *d = opendir("/proc");
	if (!d) {
		lua_pushnil(L);
		lua_pushstring(L, "cannot open /proc");
		return 2;
	}

	lua_newtable(L);
	int idx = 1;
	struct dirent *ent;
	while ((ent = readdir(d)) != NULL) {
		/* skip non-numeric entries */
		char *p = ent->d_name;
		while (*p >= '0' && *p <= '9') p++;
		if (*p != '\0' || p == ent->d_name) continue;

		char path[64];
		snprintf(path, sizeof(path), "/proc/%s/stat", ent->d_name);
		FILE *f = fopen(path, "r");
		if (!f) continue;

		char buf[1024];
		if (!fgets(buf, sizeof(buf), f)) { fclose(f); continue; }
		fclose(f);

		/* parse: pid (comm) state ppid pgrp session tty_nr ... */
		int pid, ppid, tty_nr;
		char comm[256], state;
		char *lp = strchr(buf, '(');
		char *rp = strrchr(buf, ')');
		if (!lp || !rp) continue;

		pid = atoi(buf);
		size_t clen = rp - lp - 1;
		if (clen >= sizeof(comm)) clen = sizeof(comm) - 1;
		memcpy(comm, lp + 1, clen);
		comm[clen] = '\0';

		int pgrp, session;
		if (sscanf(rp + 2, "%c %d %d %d %d", &state, &ppid, &pgrp, &session, &tty_nr) < 5)
			continue;

		/* get uid from /proc/PID/status */
		snprintf(path, sizeof(path), "/proc/%s/status", ent->d_name);
		int uid = -1;
		f = fopen(path, "r");
		if (f) {
			char line[256];
			while (fgets(line, sizeof(line), f)) {
				if (strncmp(line, "Uid:", 4) == 0) {
					uid = atoi(line + 5);
					break;
				}
			}
			fclose(f);
		}

		lua_newtable(L);
		lua_pushinteger(L, pid); lua_setfield(L, -2, "pid");
		lua_pushinteger(L, ppid); lua_setfield(L, -2, "ppid");
		lua_pushinteger(L, uid); lua_setfield(L, -2, "uid");
		lua_pushstring(L, comm); lua_setfield(L, -2, "comm");
		lua_pushlstring(L, &state, 1); lua_setfield(L, -2, "state");
		lua_pushinteger(L, tty_nr); lua_setfield(L, -2, "tty_nr");
		lua_rawseti(L, -2, idx++);
	}
	closedir(d);
	return 1;
}

#else /* BSD */

#include <sys/param.h>
#include <sys/sysctl.h>
#include <sys/user.h>
#include <fcntl.h>
#include <kvm.h>
#include <string.h>
#include <lua.h>
#include <lauxlib.h>

static int l_getprocs(lua_State *L) {
	char errbuf[_POSIX2_LINE_MAX];
#ifdef __OpenBSD__
	kvm_t *kd = kvm_openfiles(NULL, NULL, NULL, KVM_NO_FILES, errbuf);
#else
	kvm_t *kd = kvm_openfiles(NULL, "/dev/null", NULL, O_RDONLY, errbuf);
#endif
	if (!kd) {
		lua_pushnil(L);
		lua_pushstring(L, errbuf);
		return 2;
	}

	int cnt;
#ifdef __OpenBSD__
	struct kinfo_proc *procs = kvm_getprocs(kd, KERN_PROC_ALL, 0,
		sizeof(struct kinfo_proc), &cnt);
#else
	struct kinfo_proc *procs = kvm_getprocs(kd, KERN_PROC_PROC, 0, &cnt);
#endif
	if (!procs) {
		lua_pushnil(L);
		lua_pushstring(L, kvm_geterr(kd));
		kvm_close(kd);
		return 2;
	}

	lua_newtable(L);
	for (int i = 0; i < cnt; i++) {
		struct kinfo_proc *kp = &procs[i];
		lua_newtable(L);
#ifdef __OpenBSD__
		lua_pushinteger(L, kp->p_pid); lua_setfield(L, -2, "pid");
		lua_pushinteger(L, kp->p_ppid); lua_setfield(L, -2, "ppid");
		lua_pushinteger(L, kp->p_uid); lua_setfield(L, -2, "uid");
		lua_pushstring(L, kp->p_comm); lua_setfield(L, -2, "comm");
		char st[2] = { "?IIRSZT"[(kp->p_stat < 7) ? kp->p_stat : 0], '\0' };
		lua_pushstring(L, st); lua_setfield(L, -2, "state");
		lua_pushinteger(L, kp->p_tdev); lua_setfield(L, -2, "tty_nr");
#else /* FreeBSD */
		lua_pushinteger(L, kp->ki_pid); lua_setfield(L, -2, "pid");
		lua_pushinteger(L, kp->ki_ppid); lua_setfield(L, -2, "ppid");
		lua_pushinteger(L, kp->ki_uid); lua_setfield(L, -2, "uid");
		lua_pushstring(L, kp->ki_comm); lua_setfield(L, -2, "comm");
		char st[2] = { kp->ki_stat ? kp->ki_stat : '?', '\0' };
		lua_pushstring(L, st); lua_setfield(L, -2, "state");
		lua_pushinteger(L, (lua_Integer)kp->ki_tdev); lua_setfield(L, -2, "tty_nr");
#endif
		lua_rawseti(L, -2, i + 1);
	}

	kvm_close(kd);
	return 1;
}

#endif /* BSD */

static const luaL_Reg ps_funcs[] = {
	{"getprocs", l_getprocs},
	{NULL, NULL}
};

int luaopen_ps_sys(lua_State *L) {
	luaL_newlib(L, ps_funcs);
	return 1;
}
