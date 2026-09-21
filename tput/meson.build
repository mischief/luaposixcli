# SPDX-License-Identifier: ISC
install_data('tput.lua',
  rename: 'tput',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('tput', sh, args: [meson.current_source_dir() / 'test.sh'],
  env: ['LUA_CPATH=' + meson.project_build_root() / '?.so;;'],
)
