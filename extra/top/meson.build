# SPDX-License-Identifier: ISC
install_data('top.lua',
  rename: 'top',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

test('top', sh,
  args: [meson.current_source_dir() / 'test.sh'],
  env: ps_test_env,
  depends: [ps_sys],
)
