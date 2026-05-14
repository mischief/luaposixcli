# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('mkdir.lua',
  rename: 'mkdir',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('mkdir', sh, args: [meson.current_source_dir() / 'test.sh'])
