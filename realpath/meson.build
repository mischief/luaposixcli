# SPDX-License-Identifier: ISC
install_data('realpath.lua',
  rename: 'realpath',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('realpath', sh, args: [meson.current_source_dir() / 'test.sh'])
