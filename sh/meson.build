# SPDX-License-Identifier: ISC
busted = find_program('busted')
sh_prog = find_program('sh')

install_data('sh.lua',
  rename: 'sh',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

install_data(
  'lexer.lua', 'exec.lua', 'env.lua', 'expand.lua', 'compound.lua', 'test.lua',
  install_dir: lua_mod_dir / 'sh',
)

test('sh.lexer', busted,
  args: ['--lua=' + lua_name, meson.current_source_dir() / 'lexer_test.lua'],
  workdir: meson.project_source_root(),
)

test('sh.vars', busted,
  args: ['--lua=' + lua_name, meson.current_source_dir() / 'vars_test.lua'],
  workdir: meson.project_source_root(),
)

test('sh.test', busted,
  args: ['--lua=' + lua_name, meson.current_source_dir() / 'test_test.lua'],
  workdir: meson.project_source_root(),
)

test('sh.list', busted,
  args: ['--lua=' + lua_name, meson.current_source_dir() / 'list_test.lua'],
  workdir: meson.project_source_root(),
)

test('sh.cmdsub', busted,
  args: ['--lua=' + lua_name, meson.current_source_dir() / 'cmdsub_test.lua'],
  workdir: meson.project_source_root(),
)

test('sh.redir', busted,
  args: ['--lua=' + lua_name, meson.current_source_dir() / 'redir_test.lua'],
  workdir: meson.project_source_root(),
)

test('sh.compound', busted,
  args: ['--lua=' + lua_name, meson.current_source_dir() / 'compound_test.lua'],
  workdir: meson.project_source_root(),
)

test('sh.compound_multiline', busted,
  args: ['--lua=' + lua_name, meson.current_source_dir() / 'compound_multiline_test.lua'],
  workdir: meson.project_source_root(),
)

test('sh', sh_prog, args: [meson.current_source_dir() / 'test.sh'])
