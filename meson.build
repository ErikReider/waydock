project(
  'waydock',
  ['c', 'vala'],
  version: '0.1',
  meson_version: '>= 0.59.0',
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

# Run the postinstall script when installing
meson.add_install_script('build-aux/meson/postinstall.py')
