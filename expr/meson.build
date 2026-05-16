# SPDX-License-Identifier: ISC

install_data('expr.lua',
  rename: 'expr',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('expr', sh, args: [meson.current_source_dir() / 'test.sh'])
