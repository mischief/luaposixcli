# SPDX-License-Identifier: ISC
install_data('nl.lua',
  rename: 'nl',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('nl', sh, args: [meson.current_source_dir() / 'test.sh'])
