# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('logger.lua',
  rename: 'logger',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('logger', sh, args: [meson.current_source_dir() / 'test.sh'])
