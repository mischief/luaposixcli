# SPDX-License-Identifier: ISC

install_data('nohup.lua',
  rename: 'nohup',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('nohup', sh, args: [meson.current_source_dir() / 'test.sh'])
