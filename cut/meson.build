# SPDX-License-Identifier: ISC

install_data('cut.lua',
  rename: 'cut',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('cut', sh, args: [meson.current_source_dir() / 'test.sh'])
