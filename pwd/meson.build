# SPDX-License-Identifier: ISC

install_data('pwd.lua',
  rename: 'pwd',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('pwd', sh, args: [meson.current_source_dir() / 'test.sh'])
