# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('comm.lua',
  rename: 'comm',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('comm', sh, args: [meson.current_source_dir() / 'test.sh'])
