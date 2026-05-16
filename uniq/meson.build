# SPDX-License-Identifier: ISC

install_data('uniq.lua',
  rename: 'uniq',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('uniq', sh, args: [meson.current_source_dir() / 'test.sh'])
