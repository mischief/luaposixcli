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

test('awk.parser', busted,
  args: ['--lua=' + lua_name, meson.current_source_dir() / 'parser_test.lua'],
  workdir: meson.project_source_root(),
)

test('awk.eval', busted,
  args: ['--lua=' + lua_name, '--cpath=' + meson.project_build_root() / '?.so',
         meson.current_source_dir() / 'eval_test.lua'],
  workdir: meson.project_source_root(),
)
