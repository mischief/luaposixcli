# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('yes.lua',
  rename: 'yes',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('yes', sh, args: [meson.current_source_dir() / 'test.sh'])
