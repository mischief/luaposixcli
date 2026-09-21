# SPDX-License-Identifier: ISC
install_data('tsort.lua',
  rename: 'tsort',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('tsort', sh, args: [meson.current_source_dir() / 'test.sh'])
