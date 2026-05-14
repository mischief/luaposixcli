# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('sort.lua',
  rename: 'sort',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('sort', sh, args: [meson.current_source_dir() / 'test.sh'])
