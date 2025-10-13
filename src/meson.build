# Sets the version to a vala variable in Constants.vala
version = '@0@'.format(meson.project_version())
git = find_program('git', native: true, required: false)
if git.found()
  git_commit = run_command([git, 'rev-parse', '--short', 'HEAD'], check: false)
  git_branch = run_command([git, 'rev-parse', '--abbrev-ref', 'HEAD'], check: false)
  if git_commit.returncode() == 0 and git_branch.returncode() == 0
    version = '@0@ (git-@1@, branch \'@2@\')'.format(
      meson.project_version(),
      git_commit.stdout().strip(),
      git_branch.stdout().strip(),
    )
  endif
endif
version = 'waydock @0@'.format(version)
const_config_data = configuration_data()
const_config_data.set_quoted('VERSION', version)
const_config_data.set_quoted('VERSION_NUM', meson.project_version())
constants = configure_file(
  input: 'constants.vala.in',
  output: 'constants.vala',
  configuration: const_config_data,
)

app_sources = [
  'dock_item.vala',
  'dock_popover.vala',
  'dock_list.vala',
  'functions.vala',
  'icon.vala',
  'icon_state.vala',
  'main.vala',
  'pinned_list.vala',
  'icon_state_list_store.vala',
  'wlr_foreign_helper.vala',
  'window.vala',
  'unity_service.vala',
  constants,
]

assert(vala.version() >= '0.56')

app_deps = [
  dependency('gio-2.0', version: '>= 2.50'),
  dependency('gio-unix-2.0', version: '>= 2.50'),
  dependency('gtk4', version: '>= 4.14'),
  dependency('json-glib-1.0', version: '>= 1.0'),
  dependency('granite-7', version: '>= 7.5.0'),
  dependency('gtk4-layer-shell-0', version: '>= 1.1.1'),
  dependency('libadwaita-1', version: '>= 1.5.0'),
  cc.find_library('m', required: true),
  vala.find_library('posix'),
  dependency('gee-0.8'),
  dependency('wayland-client'),
  dependency('gtk4-wayland'),
  protocol_dep,
]

args = [
  '--target-glib=2.50',
]

executable(
  'waydock',
  [app_sources, app_resources],
  vala_args: args,
  dependencies: app_deps,
  install: true,
)

config_data = configuration_data()
config_data.set_quoted('JSONPATH', join_paths('/', config_path, 'configSchema.json'))
