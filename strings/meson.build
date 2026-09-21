# SPDX-License-Identifier: ISC
install_data('strings.lua',
  rename: 'strings',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('strings', sh, args: [meson.current_source_dir() / 'test.sh'])
