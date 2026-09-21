# SPDX-License-Identifier: ISC

install_data('write.lua',
  rename: 'write',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('write', sh, args: [meson.current_source_dir() / 'test.sh'])
