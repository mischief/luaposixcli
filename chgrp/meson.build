# SPDX-License-Identifier: ISC

install_data('chgrp.lua',
  rename: 'chgrp',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('chgrp', sh, args: [meson.current_source_dir() / 'test.sh'])
