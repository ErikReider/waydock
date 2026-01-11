# GSchema
compile_schemas = find_program('glib-compile-schemas', required: true)
install_data(
  'org.erikreider.waydock.gschema.xml',
  install_dir: join_paths(get_option('datadir'), 'glib-2.0/schemas'),
)

test(
  'Validate schema file',
  compile_schemas,
  args: ['--strict', '--dry-run', meson.current_source_dir()],
)

if get_option('buildtype') != 'release'
  app_resources += custom_target(
    'gschemas',
    input: 'org.erikreider.waydock.gschema.xml',
    output: 'gschemas.compiled',
    command: [
      compile_schemas,
      '--strict', meson.current_source_dir(),
      '--targetdir', '@OUTDIR@'
    ],
    install: false,
  )
  dev_env.set('GSETTINGS_SCHEMA_DIR', meson.current_build_dir())
endif

# SCSS Dependency
sassc = find_program('sassc')
assert(sassc.found())
style_css = custom_target(
  'Compiling SCSS',
  input: 'style/style.scss',
  output: 'style.css',
  command: [
    sassc,
    '-t', 'expanded',
    '@INPUT@',
    '@OUTPUT@',
  ],
  install: false,
)
message(style_css.full_path())

app_resources += gnome.compile_resources(
  'waydock-resources',
  'waydock.gresource.xml',
  dependencies: [style_css],
  c_name: 'way_dock_resources',
)
