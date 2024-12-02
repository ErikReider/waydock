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

        // Remove the unneeded Exec field codes:
        // https://specifications.freedesktop.org/desktop-entry-spec/latest/exec-variables.html
        cmdline = cmdline.replace ("%u", "").replace ("%f", "");

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

static DesktopAppInfo ? get_app_info (string ? app_id) {
    if (app_id == null) {
        return null;
    }

    string app_id_down = app_id.down ();

    // Try to get the desktop file directly
    string[] entries = {};
    if (app_id != null) {
        entries += app_id;
        entries += app_id_down;
    }
    foreach (string entry in entries) {
        var app_info = new DesktopAppInfo ("%s.desktop".printf (entry));
        // Checks if the .desktop file actually exists or not
        if (app_info is DesktopAppInfo) {
            return app_info;
        }
    }

    // Try searching for desktop file instead
    string * *[] result = DesktopAppInfo.search (app_id);
    foreach (var scores in result) {
        DesktopAppInfo ? first_choice = null;
        DesktopAppInfo ? second_choice = null;
        for (int i = 0; i < strv_length ((string *[]) scores); i++) {
            if (first_choice != null && second_choice != null) {
                break;
            }

            string * entry = scores[i];
            DesktopAppInfo app_info = new DesktopAppInfo (entry);

            if (first_choice == null && app_info.get_startup_wm_class () == app_id) {
                first_choice = app_info;
                continue;
            }
            if (second_choice == null) {
                string[] split = entry->down ().split (".");
                if (app_id_down in split) {
                    second_choice = app_info;
                    continue;
                }

                // Backup
                if (entry->down ().contains (app_id_down)) {
                    second_choice = new DesktopAppInfo (entry);
                } else if (app_info.get_name ().down () == app_id_down) {
                    second_choice = app_info;
                } else if (app_info.get_executable () == app_id) {
                    second_choice = app_info;
                }
            }
        }

        var app_info = first_choice ?? second_choice;
        // Checks if the .desktop file actually exists or not
        if (app_info is DesktopAppInfo) {
            strfreev (scores);
            return app_info;
        }
        strfreev (scores);
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

static void set_image_icon_from_app_info (DesktopAppInfo ? app_info,
                                          string ? app_id,
                                          Gtk.Image image) {
    // Fallback
    string ? icon_string = app_id;
    unowned var display = Gdk.Display.get_default ();
    if (icon_string == null
        || !Gtk.IconTheme.get_for_display (display).has_icon (icon_string)) {
        icon_string = "application-x-executable";
    }
    image.set_from_icon_name (icon_string);

    // Try setting from the desktop app info
    if (app_info != null) {
        unowned GLib.Icon ? icon = app_info.get_icon ();
        if (icon != null) {
            image.set_from_gicon (icon);
        }
    }
}
