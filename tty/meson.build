# SPDX-License-Identifier: ISC

install_data('tty.lua',
  rename: 'tty',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('tty', sh, args: [meson.current_source_dir() / 'test.sh'])
