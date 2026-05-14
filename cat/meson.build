# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('cat.lua',
  rename: 'cat',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('cat', sh, args: [meson.current_source_dir() / 'test.sh'])
