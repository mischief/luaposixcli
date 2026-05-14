# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('cal.lua',
  rename: 'cal',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('cal', sh, args: [meson.current_source_dir() / 'test.sh'])
