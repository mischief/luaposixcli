# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('chown.lua',
  rename: 'chown',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('chown', sh, args: [meson.current_source_dir() / 'test.sh'])
