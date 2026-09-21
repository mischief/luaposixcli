# SPDX-License-Identifier: ISC
install_data('pathchk.lua',
  rename: 'pathchk',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('pathchk', sh, args: [meson.current_source_dir() / 'test.sh'])
