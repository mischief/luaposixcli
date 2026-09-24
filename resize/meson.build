# SPDX-License-Identifier: ISC
install_data('resize.lua',
  rename: 'resize',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('resize', sh, args: [meson.current_source_dir() / 'test.sh'],
  env: ['LUA_CPATH=' + meson.project_build_root() / '?.so;;'],
)
