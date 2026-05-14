# SPDX-License-Identifier: ISC
sh = find_program('sh')

install_data('awk.lua',
  rename: 'awk',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

install_data(
  'lexer.lua', 'parser.lua', 'eval.lua',
  install_dir: lua_mod_dir / 'awk',
)

test('awk', sh, args: [meson.current_source_dir() / 'test.sh'])
