# SPDX-License-Identifier: ISC

install_data('cp.lua',
  rename: 'cp',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('cp', sh, args: [meson.current_source_dir() / 'test.sh'])
