# SPDX-License-Identifier: ISC

install_data('unlink.lua',
  rename: 'unlink',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('unlink', sh, args: [meson.current_source_dir() / 'test.sh'])
