# SPDX-License-Identifier: ISC

install_data('echo.lua',
  rename: 'echo',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('echo', sh, args: [meson.current_source_dir() / 'test.sh'])
