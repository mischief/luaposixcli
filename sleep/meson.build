# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('sleep.lua',
  rename: 'sleep',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('sleep', sh, args: [meson.current_source_dir() / 'test.sh'])
