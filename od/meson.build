# SPDX-License-Identifier: ISC

install_data('od.lua',
  rename: 'od',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('od', sh, args: [meson.current_source_dir() / 'test.sh'])
