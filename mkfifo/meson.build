# SPDX-License-Identifier: ISC

install_data('mkfifo.lua',
  rename: 'mkfifo',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('mkfifo', sh, args: [meson.current_source_dir() / 'test.sh'])
