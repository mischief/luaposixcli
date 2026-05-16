# SPDX-License-Identifier: ISC

install_data('ls.lua',
  rename: 'ls',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('ls', sh, args: [meson.current_source_dir() / 'test.sh'])
