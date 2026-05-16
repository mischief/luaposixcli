# SPDX-License-Identifier: ISC

install_data('tail.lua',
  rename: 'tail',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('tail', sh, args: [meson.current_source_dir() / 'test.sh'])
