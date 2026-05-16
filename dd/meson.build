# SPDX-License-Identifier: ISC

install_data('dd.lua',
  rename: 'dd',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('dd', sh, args: [meson.current_source_dir() / 'test.sh'])
