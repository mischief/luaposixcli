# SPDX-License-Identifier: ISC

install_data('uname.lua',
  rename: 'uname',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('uname', sh, args: [meson.current_source_dir() / 'test.sh'])
