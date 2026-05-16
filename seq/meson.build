# SPDX-License-Identifier: ISC

install_data('seq.lua',
  rename: 'seq',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('seq', sh, args: [meson.current_source_dir() / 'test.sh'])
