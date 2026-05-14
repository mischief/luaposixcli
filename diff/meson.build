# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('diff.lua',
  rename: 'diff',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('diff', sh, args: [meson.current_source_dir() / 'test.sh'])
