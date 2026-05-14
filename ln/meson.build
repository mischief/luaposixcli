# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('ln.lua',
  rename: 'ln',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('ln', sh, args: [meson.current_source_dir() / 'test.sh'])
