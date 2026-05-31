# SPDX-License-Identifier: ISC
project('lua-os-utils', 'c', meson_version: '>=1.1')

lua_name = get_option('lua')
lua_ver = lua_name.replace('lua', '')
lua_mod_dir = get_option('datadir') / 'lua' / lua_ver
lua_lib_dir = get_option('libdir') / 'lua' / lua_ver

stylua = find_program('stylua', required: false)
if stylua.found()
  run_target('format',
    command: [stylua, meson.project_source_root()],
  )
endif

lua_dep = dependency(lua_name, required: false)
if not lua_dep.found()
  lua_dep = dependency('lua')
endif

notposix_lib = shared_library('notposix',
  'notposix.c',
  name_prefix: '',
  dependencies: [lua_dep],
  install: true,
  install_dir: lua_lib_dir,
)

lua_prog = find_program(lua_name)
busted = find_program('busted')
test('notposix', busted,
  args: ['--lua=' + lua_name, '--cpath=' + meson.project_build_root() / '?.so',
         meson.current_source_dir() / 'notposix_test.lua'],
  workdir: meson.project_source_root(),
  depends: notposix_lib,
)

sh = find_program('sh')

foreach u : [
  'true', 'false', 'echo', 'cat', 'pwd',
  'yes', 'tee', 'wc', 'head', 'tail',
  'basename', 'dirname', 'sleep', 'env', 'tty',
  'id', 'uname', 'mktemp', 'rm', 'mkdir',
  'rmdir', 'ln', 'chmod', 'kill', 'seq',
  'ls',
  'cp', 'mv', 'touch', 'time', 'nice',
  'cmp', 'link', 'unlink', 'logname',
  'chown', 'chgrp',
  'cal',
  'date', 'printf',
  'df',
  'dd',
  'logger',
  'mkfifo',
  'od', 'pr',
  'ps',
  'sort',
  'uniq',
  'cut', 'tr', 'expr',
  'nohup', 'xargs',
  'grep',
  'sed',
  'renice',
  'paste', 'fold', 'expand', 'unexpand', 'comm',
  'find', 'du',
  'tar', 'bc',
  'diff', 'patch',
  'awk',
  'sh',
  'make',
  'ed',
  'ping',
]
  subdir(u)
endforeach
