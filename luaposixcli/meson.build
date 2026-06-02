# SPDX-License-Identifier: ISC

sys_link_args = []
if host_machine.system() == 'freebsd'
  sys_link_args += ['-Wl,-z,undefs']
endif

luaposixcli_sys = shared_library('sys', 'sys.c',
  name_prefix: '',
  dependencies: [lua_dep],
  link_args: sys_link_args,
  install: true,
  install_dir: lua_lib_dir / 'luaposixcli',
)

test_env = environment()
test_env.append('LUA_CPATH', meson.project_build_root() / '?.so;;', separator: ';')

test('luaposixcli.sys', busted,
  args: ['--lua=' + lua_name, meson.current_source_dir() / 'sys_test.lua'],
  workdir: meson.project_source_root(),
  env: test_env,
  depends: luaposixcli_sys,
)
