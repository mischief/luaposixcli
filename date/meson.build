# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('date.lua',
  rename: 'date',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('date', sh, args: [meson.current_source_dir() / 'test.sh'])
