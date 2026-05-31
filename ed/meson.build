# SPDX-License-Identifier: ISC

install_data('ed.lua',
  rename: 'ed',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

install_data('ex.lua',
  rename: 'ex',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

install_data('vi.lua',
  rename: 'vi',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

install_data(
  'buffer.lua',
  'terminfo.lua',
  install_dir: lua_mod_dir / 'ed',
)

test('ed.buffer', busted,
  args: [
    '--lua=' + lua_name,
    '--cpath=' + meson.current_build_dir() / '?.so',
    meson.current_source_dir() / 'buffer_test.lua',
  ],
  workdir: meson.project_source_root(),
)
