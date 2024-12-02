static Settings self_settings;

static WlrForeignHelper foreign_helper;

class PinnedList {
    public List<string> pinned;

    public signal void pinned_removed (string app_id);
    public signal void pinned_added (string app_id);

    public PinnedList () {
        get_pinned ();
    }

    public void get_pinned () {
        pinned = new List<string>();

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

        string[] array = self_settings.get_value ("pinned").get_strv ();
        foreach (string app_id in array) {
            pinned.append (app_id);
        }
    }

    public void set_pinned () {
        if (!self_settings.settings_schema.has_key ("pinned")) {
            warning ("Could not set pinned");
            return;
        }

        string[] pinned_array = {};
        foreach (var app_id in pinned) {
            pinned_array += app_id;
        }

        bool result = self_settings.set_strv ("pinned", pinned_array);
        if (!result) {
            warning ("Could not set pinned: %u", pinned.length ());
            return;
        }
    }

    public void remove_pinned (string app_id) {
        unowned List<string> node = pinned.find_custom (app_id, strcmp);
        if (node != null) {
            pinned.remove_link (node);
            set_pinned ();
            pinned_removed (app_id);
        }
    }

    public void add_pinned (string app_id) {
        if (pinned.find (app_id) == null) {
            pinned.append (app_id);
            set_pinned ();
            pinned_added (app_id);
        }
    }
}

static PinnedList pinnedList;

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

    pinnedList = new PinnedList ();

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
