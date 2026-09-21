# SPDX-License-Identifier: ISC

install_data('who.lua',
  rename: 'who',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('who', sh, args: [meson.current_source_dir() / 'test.sh'])
