# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('xargs.lua',
  rename: 'xargs',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('xargs', sh, args: [meson.current_source_dir() / 'test.sh'])
