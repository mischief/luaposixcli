# SPDX-License-Identifier: ISC

install_data('env.lua',
  rename: 'env',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('env', sh, args: [meson.current_source_dir() / 'test.sh'],
  env: ['LUA_CPATH=' + meson.project_build_root() / '?.so;;'],
  depends: notposix_lib,
)
