# SPDX-License-Identifier: ISC

sys_link_args = []
if host_machine.system() == 'freebsd'
  sys_link_args += ['-Wl,-z,undefs']
endif

shared_library('sys', 'sys.c',
  name_prefix: '',
  dependencies: [lua_dep],
  link_args: sys_link_args,
  install: true,
  install_dir: lua_lib_dir / 'luaposixcli',
)
