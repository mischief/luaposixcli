# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('awk.lua',
  rename: 'awk',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('awk', sh, args: [meson.current_source_dir() / 'test.sh'])
