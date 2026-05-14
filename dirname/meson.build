# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('dirname.lua',
  rename: 'dirname',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('dirname', sh, args: [meson.current_source_dir() / 'test.sh'])
