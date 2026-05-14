# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('head.lua',
  rename: 'head',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('head', sh, args: [meson.current_source_dir() / 'test.sh'])
