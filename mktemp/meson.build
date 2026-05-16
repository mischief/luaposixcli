# SPDX-License-Identifier: ISC

install_data('mktemp.lua',
  rename: 'mktemp',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('mktemp', sh, args: [meson.current_source_dir() / 'test.sh'])
