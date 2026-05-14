# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('link.lua',
  rename: 'link',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('link', sh, args: [meson.current_source_dir() / 'test.sh'])
