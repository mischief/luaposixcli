# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('nice.lua',
  rename: 'nice',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('nice', sh, args: [meson.current_source_dir() / 'test.sh'])
