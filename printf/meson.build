# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('printf.lua',
  rename: 'printf',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('printf', sh, args: [meson.current_source_dir() / 'test.sh'])
