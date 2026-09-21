# SPDX-License-Identifier: ISC
install_data('split.lua',
  rename: 'split',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('split', sh, args: [meson.current_source_dir() / 'test.sh'])
