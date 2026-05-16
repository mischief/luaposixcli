# SPDX-License-Identifier: ISC

install_data('du.lua',
  rename: 'du',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('du', sh, args: [meson.current_source_dir() / 'test.sh'])
