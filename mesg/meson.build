# SPDX-License-Identifier: ISC

install_data('mesg.lua',
  rename: 'mesg',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('mesg', sh, args: [meson.current_source_dir() / 'test.sh'])
