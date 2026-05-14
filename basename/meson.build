# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('basename.lua',
  rename: 'basename',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('basename', sh, args: [meson.current_source_dir() / 'test.sh'])
