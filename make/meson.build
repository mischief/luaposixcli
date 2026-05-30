# SPDX-License-Identifier: ISC

install_data('make.lua',
  rename: 'make',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

install_data(
  'parser.lua',
  'eval.lua',
  'exec.lua',
  'jobserver.lua',
  install_dir: lua_mod_dir / 'make',
)

test('make.parser', busted,
  args: [
    '--lua=' + lua_name,
    '--cpath=' + meson.current_build_dir() / '?.so',
    meson.current_source_dir() / 'parser_test.lua',
  ],
  workdir: meson.project_source_root(),
)

test('make.eval', busted,
  args: [
    '--lua=' + lua_name,
    '--cpath=' + meson.current_build_dir() / '?.so',
    meson.current_source_dir() / 'eval_test.lua',
  ],
  workdir: meson.project_source_root(),
)

test('make.sh', sh, args: [meson.current_source_dir() / 'test.sh'],
  env: ['LUA_CPATH=' + meson.project_build_root() / '?.so;;'],
  depends: notposix_lib,
)
