# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('id.lua',
  rename: 'id',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('id', sh, args: [meson.current_source_dir() / 'test.sh'])
