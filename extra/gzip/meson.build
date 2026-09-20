# SPDX-License-Identifier: ISC
install_data('gzip.lua',
  rename: 'gzip',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

foreach name : ['gunzip', 'zcat']
  install_symlink(name,
    install_dir: get_option('bindir'),
    pointing_to: 'gzip',
  )
endforeach

test('gzip', sh, args: [meson.current_source_dir() / 'test.sh'])
