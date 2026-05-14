# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('mv.lua',
  rename: 'mv',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('mv', sh, args: [meson.current_source_dir() / 'test.sh'])
