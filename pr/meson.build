# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('pr.lua',
  rename: 'pr',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('pr', sh, args: [meson.current_source_dir() / 'test.sh'])
