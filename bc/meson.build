# SPDX-License-Identifier: ISC

install_data('bc.lua',
  rename: 'bc',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

install_data('bignum.lua',
  install_dir: lua_mod_dir / 'bc',
)

test('bc', sh, args: [meson.current_source_dir() / 'test.sh'])
