# SPDX-License-Identifier: ISC

ps_deps = [lua_dep]
if host_machine.system() != 'linux'
  ps_deps += meson.get_compiler('c').find_library('kvm')
endif

ps_sys = shared_library('sys', 'sys.c',
  dependencies: ps_deps,
  name_prefix: '',
  install: true,
  install_dir: lua_lib_dir / 'ps',
)

install_data('ps.lua',
  rename: 'ps',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

ps_test_env = environment()
ps_test_env.append('LUA_CPATH', meson.project_build_root() / '?.so;;', separator: ';')

test('ps', sh,
  args: [meson.current_source_dir() / 'test.sh'],
  env: ps_test_env,
  depends: [ps_sys, luaposixcli_sys],
)
