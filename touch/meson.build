# SPDX-License-Identifier: ISC

install_data('touch.lua',
  rename: 'touch',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('touch', sh, args: [meson.current_source_dir() / 'test.sh'])
