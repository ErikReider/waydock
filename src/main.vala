static Settings self_settings;

static WlrForeignHelper foreign_helper;

static List<string> pinned;

static List<AppInfo> all_app_infos;

public static int main (string[] args) {
    Gtk.init ();
    Adw.init ();

    self_settings = new Settings ("org.erikreider.swaync");

    // All app infos
    all_app_infos = AppInfo.get_all ();
    AppInfoMonitor app_info_monitor = AppInfoMonitor.get ();
    app_info_monitor.changed.connect (() => {
        all_app_infos = AppInfo.get_all ();
    });

    foreign_helper = new WlrForeignHelper ();

#if USE_GLOBAL_GSCHEMA
    // Use the global compiled gschema in /usr/share/glib-2.0/schemas/*
    self_settings = new Settings ("org.erikreider.swaysettings");
#else
    message ("Using local GSchema");
    // Meant for use in development.
    // Uses the compiled gschema in SwaySettings/data/
    // Should never be used in production!
    string settings_dir = Path.build_path (Path.DIR_SEPARATOR_S,
                                           Environment.get_current_dir (),
                                           "data");
    try {
        SettingsSchemaSource sss = new SettingsSchemaSource.from_directory (settings_dir, null, false);
        SettingsSchema schema = sss.lookup ("org.erikreider.waydock", false);
        if (sss.lookup == null) {
            error ("ID not found.\n");
            return 0;
        }
        self_settings = new Settings.full (schema, null, null);
    } catch (Error e) {
        error ("Could not load GSchema: %s", e.message);
    }
#endif

    get_pinned ();

    // Load custom CSS
    Gtk.CssProvider css_provider = new Gtk.CssProvider ();
    css_provider.load_from_resource (
        "/org/erikreider/waydock/style.css");
    Gtk.StyleContext.add_provider_for_display (
        Gdk.Display.get_default (),
        css_provider,
        Gtk.STYLE_PROVIDER_PRIORITY_USER);

    var app = new Gtk.Application ("org.erikreider.waydock",
                                   ApplicationFlags.FLAGS_NONE);

    app.activate.connect (() => {
        Window ? win = (Window) app.active_window;
        if (win == null) {
            win = new Window (app);
            foreign_helper.start ();
        }
        win.present ();
    });

    return app.run ();
}

public static unowned Wl.Display get_wl_display () {
    unowned var display = Gdk.Display.get_default ();
    if (display is Gdk.Wayland.Display) {
        return ((Gdk.Wayland.Display) display).get_wl_display ();
    }
    GLib.error ("Only supports Wayland!");
}

public static void set_image_icon_from_app_info (DesktopAppInfo ? app_info,
                                                 string app_id,
                                                 Gtk.Image image) {
    // Fallback
    string icon_string = app_id;
    unowned var display = Gdk.Display.get_default ();
    if (!Gtk.IconTheme.get_for_display (display).has_icon (icon_string)) {
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

public static void get_pinned () {
    if (!self_settings.settings_schema.has_key ("pinned")) {
        return;
    }
    var v_type = self_settings.settings_schema.get_key ("pinned").get_value_type ();
    if (!v_type.is_array ()) {
        stderr.printf (
            "Set GSettings error:" +
            " Set value type \"array\" not equal to gsettings type \"%s\"\n",
            v_type);
        return;
    }

    pinned = new List<string>();
    string[] array = self_settings.get_value ("pinned").get_strv ();
    foreach (string app_id in array) {
        pinned.append (app_id);
    }
}

public static DesktopAppInfo ? get_app_info (string app_id) {
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

            string[] split = entry->down ().split (".");
            if (first_choice == null && app_id_down in split) {
                first_choice = new DesktopAppInfo (entry);
                continue;
            }
            if (second_choice == null) {
                if (entry->down ().contains (app_id_down)) {
                    second_choice = new DesktopAppInfo (entry);
                    continue;
                }
                // Backup, check executable name
                var app_info = new DesktopAppInfo (entry);
                if (app_info.get_startup_wm_class () == app_id) {
                    second_choice = app_info;
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
