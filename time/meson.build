# SPDX-License-Identifier: ISC

install_data('time.lua',
  rename: 'time',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('time', sh, args: [meson.current_source_dir() / 'test.sh'])
