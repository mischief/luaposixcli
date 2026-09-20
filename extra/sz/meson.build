# SPDX-License-Identifier: ISC
install_data('sz.lua',
  rename: 'sz',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('zmodem', sh, args: [meson.current_source_dir() / 'test.sh'], timeout: 60)
