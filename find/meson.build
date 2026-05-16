# SPDX-License-Identifier: ISC

install_data('find.lua',
  rename: 'find',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('find', sh, args: [meson.current_source_dir() / 'test.sh'])
