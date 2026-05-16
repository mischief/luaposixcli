# SPDX-License-Identifier: ISC

install_data('wc.lua',
  rename: 'wc',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('wc', sh, args: [meson.current_source_dir() / 'test.sh'])
