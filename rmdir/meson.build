# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('rmdir.lua',
  rename: 'rmdir',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('rmdir', sh, args: [meson.current_source_dir() / 'test.sh'])
