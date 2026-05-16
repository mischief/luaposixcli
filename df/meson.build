# SPDX-License-Identifier: ISC

install_data('df.lua',
  rename: 'df',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('df', sh, args: [meson.current_source_dir() / 'test.sh'])
