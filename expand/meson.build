# SPDX-License-Identifier: ISC

install_data('expand.lua',
  rename: 'expand',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('expand', sh, args: [meson.current_source_dir() / 'test.sh'])
