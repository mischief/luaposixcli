# SPDX-License-Identifier: ISC
project('luaposixcli', 'c', meson_version: '>=1.1')

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

lua_prog = find_program(lua_name)
busted = find_program('busted')
sh = find_program('sh')

subdir('luaposixcli')

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
]
  subdir(u)
endforeach

if get_option('extras')
  subdir('extra')
endif
