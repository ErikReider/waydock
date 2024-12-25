# vim: syntax=spec
Name:       waydock-git
Version:    0.1.0
Release:    1%{?dist}
Summary:    A dock that supports wlroots-based WMs
License:    GPLv3
URL:        https://github.com/ErikReider/waydock
VCS:        {{{ git_repo_vcs }}}
Source:     {{{ git_repo_pack }}}

BuildRequires: meson >= 0.60.0
BuildRequires: vala
BuildRequires: git

BuildRequires: pkgconfig(gio-2.0) >= 2.50
BuildRequires: pkgconfig(gio-unix-2.0) >= 2.50
BuildRequires: pkgconfig(gtk4) >= 4.14
BuildRequires: pkgconfig(json-glib-1.0) >= 1.0
BuildRequires: pkgconfig(granite-7) >= 7.5.0
BuildRequires: pkgconfig(gtk4-layer-shell-0) >= 1.0.4
BuildRequires: pkgconfig(libadwaita-1) >= 1.5.0
BuildRequires: pkgconfig(gee-0.8)
BuildRequires: pkgconfig(gtk4-wayland)
BuildRequires: pkgconfig(wayland-client)
Requires: glib2
Requires: gtk4-layer-shell

%description
A dock that supports wlroots-based WMs

%prep
{{{ git_repo_setup_macro }}}

%build
%meson
%meson_build

%install
%meson_install

%files
%doc README.md
%{_bindir}/waydock
%license LICENSE
%{_datadir}/glib-2.0/schemas/org.erikreider.waydock.gschema.xml

# Changelog will be empty until you make first annotated Git tag.
%changelog
{{{ git_repo_changelog }}}