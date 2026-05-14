# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('false.lua',
  rename: 'false',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('false', sh, args: [meson.current_source_dir() / 'test.sh'])
