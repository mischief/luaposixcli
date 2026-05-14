# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('tr.lua',
  rename: 'tr',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('tr', sh, args: [meson.current_source_dir() / 'test.sh'])
