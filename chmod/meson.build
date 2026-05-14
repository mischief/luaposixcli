# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('chmod.lua',
  rename: 'chmod',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('chmod', sh, args: [meson.current_source_dir() / 'test.sh'])
