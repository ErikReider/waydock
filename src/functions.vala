static Variant make_platform_data (DesktopAppInfo info,
                                   KeyFile keyfile,
                                   AppLaunchContext ? launch_context) {
    VariantBuilder builder = new VariantBuilder (VariantType.VARDICT);

    if (launch_context != null) {
        List launched_files = new List<File> ();

        try {
            bool startup_notify = keyfile.get_boolean (
                KeyFileDesktop.GROUP, KeyFileDesktop.KEY_STARTUP_NOTIFY);
            if (startup_notify) {
                string ? sn_id = launch_context.get_startup_notify_id (info, launched_files);
                if (sn_id != null) {
                    builder.add ("{sv}",
                                 "desktop-startup-id",
                                 new Variant.string (sn_id));
                    builder.add ("{sv}",
                                 "activation-token",
                                 new Variant.string (sn_id));
                }
            }
        } catch (Error e) {
            // no-op
        }
    }

    return builder.end ();
}

static string object_path_from_appid (string appid) {
    string appid_path = "/".concat (appid, null);

    for (char * iter = appid_path; *iter != '\0'; iter++) {
        if (*iter == '.') {
            *iter = '/';
        }

        if (*iter == '-') {
            *iter = '_';
        }
    }

    return appid_path;
}

static bool launch_dbus_action (string ? app_id,
                                DesktopAppInfo ? app_info,
                                KeyFile ? keyfile,
                                string ? action_name) {
    // Try to activate action before executing
    try {
        DBusConnection ? conn = Bus.get_sync (BusType.SESSION, null);
        if (conn != null && app_id != null && DBus.is_name (app_id)) {
            AppLaunchContext ctx = new AppLaunchContext ();
            string object_path = object_path_from_appid (app_id);

            conn.call_sync (
                app_id,
                object_path,
                "org.freedesktop.Application",
                "ActivateAction",
                new Variant (
                    "(sav@a{sv})",
                    action_name,
                    null,
                    make_platform_data (app_info, keyfile, ctx)),
                null,
                DBusCallFlags.NONE,
                -1,
                null);
            return true;
        }
    } catch (Error e) {
        warning ("ERROR: %s\n", e.message);
    }
    return false;
}

static void detach_child () {
    Posix.setsid ();

    Posix.FILE ? file = Posix.FILE.open ("/dev/null", "w+b");
    int fd = file.fileno ();
    (unowned Posix.FILE)[] streams = { Posix.stdin, Posix.stdout, Posix.stderr };
    foreach (var stream in streams) {
        int stream_fd = stream.fileno ();
        stream.close ();
        Posix.dup2 (fd, stream_fd);
    }
}

// Remove the unneeded Exec field codes:
// https://specifications.freedesktop.org/desktop-entry-spec/latest/exec-variables.html
static string clean_exec (string exec) {
    try {
      Regex regex = new Regex ("(%f|%F|%u|%U|%d|%D|%n|%N|%i|%c|%k|%v|%m)");
      return regex.replace (exec, exec.length, 0, "");
    } catch (RegexError e) {
      stderr.printf ("RegexError: %s\n", e.message);
    }
    return exec;
}

static void launch_application (string ? app_id,
                                DesktopAppInfo ? app_info,
                                KeyFile ? keyfile,
                                string ? action_name) {
    if (app_info == null) {
        return;
    }

    try {
        string ? cmdline = null;
        if (action_name != null) {
            if (launch_dbus_action (app_id, app_info, keyfile, action_name)) {
                return;
            }

            cmdline = keyfile.get_string (
                "Desktop Action %s".printf (action_name),
                KeyFileDesktop.KEY_EXEC);
        } else {
            cmdline = app_info.get_commandline ();
        }

        if (cmdline == null) {
            return;
        }

        cmdline = clean_exec (cmdline);

        string[] argvp = {};
        Shell.parse_argv (cmdline, out argvp);

        string[] spawn_env = Environ.get ();

        Process.spawn_async (
            Environment.get_home_dir (),
            argvp,
            spawn_env,
            SpawnFlags.SEARCH_PATH_FROM_ENVP | SpawnFlags.SEARCH_PATH,
            detach_child,
            null);
    } catch (Error e) {
        error ("Launch error: %s", e.message);
    }
}

private static DesktopAppInfo ? try_app_info_search (string app_id, string test_id) {
    // Try to get the desktop file directly
    string[] entries = {
        app_id,
        "%s.desktop".printf (app_id),
    };
    foreach (string entry in entries) {
        var app_info = new DesktopAppInfo (entry);
        // Checks if the .desktop file actually exists or not
        if (app_info is DesktopAppInfo) {
            return app_info;
        }
    }

    // Try searching for desktop file instead
    string * *[] result = DesktopAppInfo.search (test_id);
    foreach (var scores in result) {
        DesktopAppInfo ? first_choice = null;
        DesktopAppInfo ? second_choice = null;
        for (int i = 0; i < strv_length ((string *[]) scores); i++) {
            if (first_choice != null && second_choice != null) {
                break;
            }

            string * entry = scores[i];
            DesktopAppInfo ? app_info = new DesktopAppInfo (entry);
            if (app_info == null) {
                continue;
            }

            string ? wm_class = app_info.get_startup_wm_class ();
            if (first_choice == null && wm_class != null
                && (wm_class == app_id || wm_class == test_id)) {
                first_choice = app_info;
                continue;
            }
            if (second_choice == null) {
                string[] split = entry->split (".");
                if (app_id in split) {
                    second_choice = app_info;
                    continue;
                }

                // Backup
                if (entry->contains (app_id)) {
                    second_choice = new DesktopAppInfo (entry);
                } else if (app_info.get_name ()?.down () == app_id.down ()) {
                    second_choice = app_info;
                } else if (app_info.get_executable () == app_id) {
                    second_choice = app_info;
                }
            }
        }

        // Checks if the .desktop file actually exists or not
        unowned DesktopAppInfo ? app_info = first_choice ?? second_choice;
        if (app_info is DesktopAppInfo) {
            strfreev (scores);
            return app_info;
        }
        strfreev (scores);
    }

    return null;
}

static DesktopAppInfo ? get_app_info (string ? app_id) {
    if (app_id == null) {
        return null;
    }

    string[] app_ids = {
        app_id,
        app_id.down (),
    };
    // org.mozilla.firefox -> firefox
    int start = app_id.last_index_of_char ('.');
    app_ids += app_id.substring (start + 1);
    // ca.desrt.dconf-editor -> ca.desrt.dconf
    start = app_id.index_of_char ('-');
    app_ids += app_id.substring (0, start);

    foreach (string id in app_ids) {
        DesktopAppInfo? info = try_app_info_search (app_id, id);
        if (info is DesktopAppInfo) {
            return info;
        }
    }

    return null;
}

static unowned Wl.Display get_wl_display () {
    unowned var display = Gdk.Display.get_default ();
    if (display is Gdk.Wayland.Display) {
        return ((Gdk.Wayland.Display) display).get_wl_display ();
    }
    GLib.error ("Only supports Wayland!");
}

static Gdk.Paintable ? get_paintable_from_app_info (DesktopAppInfo ? app_info,
                                                    string ? app_id,
                                                    int size,
                                                    int scale_factor) {
    unowned var display = Gdk.Display.get_default ();
    unowned Gtk.IconTheme theme = Gtk.IconTheme.get_for_display (display);

    // Fallback
    string ? icon_string = app_id;
    if (icon_string == null || !theme.has_icon (icon_string)) {
        icon_string = "application-x-executable";
    }
    Gtk.IconPaintable ? paintable = theme.lookup_icon (
        icon_string, null, size, scale_factor,
        Gtk.TextDirection.NONE, 0);

    // Try setting from the desktop app info
    if (app_info == null) {
        return paintable;
    }
    unowned GLib.Icon ? icon = app_info.get_icon ();
    if (icon is ThemedIcon) {
        unowned ThemedIcon t_icon = (ThemedIcon) icon;
        foreach (string name in t_icon.names) {
            if (!theme.has_icon (name)) {
                continue;
            }
            Gtk.IconPaintable ? icon_paintable = theme.lookup_by_gicon (
                icon, size, scale_factor, Gtk.TextDirection.NONE, 0);
            if (icon_paintable != null) {
                return icon_paintable;
            }
        }
    } else if (icon is FileIcon) {
        unowned FileIcon f_icon = icon as FileIcon;
        return new Gtk.IconPaintable.for_file (f_icon.file, size, scale_factor);
    } else {
        return paintable;
    }

    return paintable;
}

static void set_image_icon_from_app_info (DesktopAppInfo ? app_info,
                                          string ? app_id,
                                          Gtk.Image image) {
    unowned var display = Gdk.Display.get_default ();
    unowned Gtk.IconTheme theme = Gtk.IconTheme.get_for_display (display);

    // Fallback
    string ? icon_string = app_id;
    if (icon_string == null || !theme.has_icon (icon_string)) {
        icon_string = "application-x-executable";
    }
    image.set_from_icon_name (icon_string);

    // Try setting from the desktop app info
    if (app_info != null) {
        unowned GLib.Icon ? icon = app_info.get_icon ();
        if (icon != null && theme.has_gicon (icon)) {
            image.set_from_gicon (icon);
            return;
        }
    }
}

/**
 * Copy of g_list_index but with custom compare function.
 * Needed due to the regular function comparing the pointers which doesn't
 * work for strings.
 */
static int list_index<G> (List<G> list, G data, CompareFunc<G> func) {
    int i = 0;
    while (list != null) {
        if (func (list.data, data) == 0)
            return i;
        i++;
        list = list.next;
    }

    return -1;
}
