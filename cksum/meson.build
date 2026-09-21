# SPDX-License-Identifier: ISC
install_data('cksum.lua',
  rename: 'cksum',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('cksum', sh, args: [meson.current_source_dir() / 'test.sh'])
