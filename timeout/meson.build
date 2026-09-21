# SPDX-License-Identifier: ISC
install_data('timeout.lua',
  rename: 'timeout',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('timeout', sh, args: [meson.current_source_dir() / 'test.sh'])
