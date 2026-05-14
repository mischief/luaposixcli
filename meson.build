# SPDX-License-Identifier: ISC
project('lua-os-utils', 'c', meson_version: '>=1.0')

stylua = find_program('stylua', required: false)
if stylua.found()
  run_target('format',
    command: [stylua, meson.project_source_root()],
  )
endif

lua54 = dependency('lua5.4', required: false)
if not lua54.found()
  lua54 = dependency('lua')
endif

shared_library('notposix',
  'notposix.c',
  name_prefix: '',
  dependencies: [lua54],
  install: true,
  install_dir: get_option('libdir') / 'lua' / '5.4',
)

busted = find_program('busted')
test('notposix', busted,
  args: ['--lua=lua5.4', '--cpath=' + meson.project_build_root() / '?.so',
         meson.current_source_dir() / 'notposix_test.lua'],
  workdir: meson.project_source_root(),
)

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
  'awk',
  'sh',
]
  subdir(u)
endforeach
