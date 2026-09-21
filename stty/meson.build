# SPDX-License-Identifier: ISC
install_data('stty.lua',
  rename: 'stty',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('stty', sh, args: [meson.current_source_dir() / 'test.sh'],
  env: ['LUA_CPATH=' + meson.project_build_root() / '?.so;;'],
)
