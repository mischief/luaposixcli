# SPDX-License-Identifier: ISC

install_data('paste.lua',
  rename: 'paste',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('paste', sh, args: [meson.current_source_dir() / 'test.sh'])
