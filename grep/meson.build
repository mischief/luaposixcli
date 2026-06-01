# SPDX-License-Identifier: ISC

install_data('grep.lua',
  rename: 'grep',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('grep', sh, args: [meson.current_source_dir() / 'test.sh'],
  env: ['LUA_CPATH=' + meson.project_build_root() / '?.so;;'],
)
