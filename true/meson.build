# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('true.lua',
  rename: 'true',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('true', sh, args: [meson.current_source_dir() / 'test.sh'])
