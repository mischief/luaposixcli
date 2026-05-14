# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('ps.lua',
  rename: 'ps',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('ps', sh, args: [meson.current_source_dir() / 'test.sh'])
