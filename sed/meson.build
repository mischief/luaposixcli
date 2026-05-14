# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('sed.lua',
  rename: 'sed',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('sed', sh, args: [meson.current_source_dir() / 'test.sh'],
  env: ['LUA_CPATH=' + meson.project_build_root() / '?.so;;'],
)
