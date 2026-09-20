# SPDX-License-Identifier: ISC
install_data('fetch.lua',
  rename: 'fetch',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('fetch', sh, args: [meson.current_source_dir() / 'test.sh'], timeout: 30)
