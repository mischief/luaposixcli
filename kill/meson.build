# SPDX-License-Identifier: ISC

install_data('kill.lua',
  rename: 'kill',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('kill', sh, args: [meson.current_source_dir() / 'test.sh'])
