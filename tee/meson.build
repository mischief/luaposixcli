# SPDX-License-Identifier: ISC

install_data('tee.lua',
  rename: 'tee',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('tee', sh, args: [meson.current_source_dir() / 'test.sh'])
