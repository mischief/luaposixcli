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

install_data('term.lua', 'util.lua', 'zmodem.lua', 'http.lua', 'tcp.lua',
  install_dir: lua_mod_dir / 'luaposixcli')

# tar -z needs these, so they install with the rest of the modules.
install_data(
  'zlib/init.lua', 'zlib/deflate.lua', 'zlib/inflate.lua',
  'zlib/gzip.lua', 'zlib/store.lua',
  install_dir: lua_mod_dir / 'luaposixcli' / 'zlib',
)

test_env = environment()
test_env.append('LUA_CPATH', meson.project_build_root() / '?.so;;', separator: ';')

if busted.found()
  test('luaposixcli.util', busted,
    args: ['--lua=' + lua_name, meson.current_source_dir() / 'util_test.lua'],
    workdir: meson.project_source_root(),
  )

  test('luaposixcli.sys', busted,
    args: ['--lua=' + lua_name, meson.current_source_dir() / 'sys_test.lua'],
    workdir: meson.project_source_root(),
    env: test_env,
    depends: luaposixcli_sys,
  )
endif
