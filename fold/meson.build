# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('fold.lua',
  rename: 'fold',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('fold', sh, args: [meson.current_source_dir() / 'test.sh'])
