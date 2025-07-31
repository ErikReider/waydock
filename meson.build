project(
  'waydock',
  ['c', 'vala'],
  version: '0.1',
  meson_version: '>= 0.60.0',
  default_options: ['warning_level=2'],
)

add_project_arguments(['-Wno-error=int-conversion'], language: 'c')
add_project_arguments(['--enable-gobject-tracing'], language: 'vala')
add_project_arguments(['--enable-checking'], language: 'vala')

cc = meson.get_compiler('c')
vala = meson.get_compiler('vala')

gnome = import('gnome')

config_path = join_paths(get_option('sysconfdir'), 'xdg', 'waydock')

protocol_dep = []
subdir('protocols')

app_resources = []

subdir('data')
subdir('src')

conf_data = configuration_data()
conf_data.set('bindir', join_paths(get_option('prefix'), get_option('bindir')))

# Systemd service unit
dep_systemd = dependency('systemd')
if dep_systemd.found()
  systemd_service_install_dir = dep_systemd.get_variable(pkgconfig: 'systemduserunitdir')
else
  systemd_service_install_dir = join_paths(get_option('libdir'), 'systemd', 'user')
endif
configure_file(
  configuration: conf_data,
  input: 'services/systemd/waydock.service.in',
  output: '@BASENAME@',
  install_dir: systemd_service_install_dir,
)

# Run the postinstall script when installing
meson.add_install_script('build-aux/meson/postinstall.py')
