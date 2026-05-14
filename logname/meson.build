# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('logname.lua',
  rename: 'logname',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('logname', sh, args: [meson.current_source_dir() / 'test.sh'])
