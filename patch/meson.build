# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('patch.lua',
  rename: 'patch',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('patch', sh, args: [meson.current_source_dir() / 'test.sh'])
