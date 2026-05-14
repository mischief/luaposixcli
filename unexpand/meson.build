# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('unexpand.lua',
  rename: 'unexpand',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('unexpand', sh, args: [meson.current_source_dir() / 'test.sh'])
