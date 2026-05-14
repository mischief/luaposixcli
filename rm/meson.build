# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('rm.lua',
  rename: 'rm',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('rm', sh, args: [meson.current_source_dir() / 'test.sh'])
