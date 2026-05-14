# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('cmp.lua',
  rename: 'cmp',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('cmp', sh, args: [meson.current_source_dir() / 'test.sh'])
