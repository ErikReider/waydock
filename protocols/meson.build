dep_scanner = dependency('wayland-scanner', native: true)
prog_scanner = find_program(dep_scanner.get_variable(pkgconfig: 'wayland_scanner'))

protocol_file = files(
  'wlr-foreign-toplevel-management-unstable-v1.xml',
)

protocol_sources = []
protocol_sources += custom_target(
  'wlr-foreign-toplevel-management-client-protocol.h',
  command: [prog_scanner, 'client-header', '@INPUT@', '@OUTPUT@'],
  input: protocol_file,
  output: 'wlr-foreign-toplevel-management-client-protocol.h',
)

output_type = 'private-code'
if dep_scanner.version().version_compare('< 1.14.91')
  output_type = 'code'
endif
protocol_sources += custom_target(
  'wlr-foreign-toplevel-management-protocol.c',
  command: [prog_scanner, output_type, '@INPUT@', '@OUTPUT@'],
  input: protocol_file,
  output: 'wlr-foreign-toplevel-management-protocol.c',
)

protocol_dep = declare_dependency(
  dependencies: [
    vala.find_library('wlr-foreign-toplevel-management-unstable-v1', dirs: meson.current_source_dir()),
    dependency('wayland-client'),
  ],
  include_directories: include_directories('.'),
  sources: protocol_sources,
)
