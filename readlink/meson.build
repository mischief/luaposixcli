# SPDX-License-Identifier: ISC
install_data('readlink.lua',
  rename: 'readlink',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('readlink', sh, args: [meson.current_source_dir() / 'test.sh'])
