# SPDX-License-Identifier: ISC
sh = find_program('sh')
busted = find_program('busted')

install_data('tar.lua',
  rename: 'tar',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

install_data('format.lua',
  install_dir: lua_mod_dir / 'tar',
)

test('tar', sh, args: [meson.current_source_dir() / 'test.sh'])

test('tar.format', busted,
  args: ['--lua=' + lua_name, meson.current_source_dir() / 'format_test.lua'],
  workdir: meson.project_source_root(),
)
