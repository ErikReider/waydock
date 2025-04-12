public enum direction {
    // TODO: Change to start/end
    LEFT = 0,
    RIGHT = 1,
    NONE = 2;
}

static Settings self_settings;

static WlrForeignHelper foreign_helper;

static PinnedList pinnedList;

static List<AppInfo> all_app_infos;

static void print_help (string program) {
    print ("Usage:\n");
    print ("\t %s <OPTION>\n".printf (program));
    print ("Help:\n");
    print ("\t -h, --help \t\t Show help options\n");
    print ("\t -v, --version \t\t Prints version\n");
}

static void parse_args (string[] args) {
    foreach (unowned string arg in args[1:]) {
        switch (arg) {
            case "--version":
                print ("%s\n", Constants.VERSION);
                Process.exit (0);
            case "--help":
                print_help (args[0]);
                Process.exit (0);
            default:
                print_help (args[0]);
                Process.exit (1);
        }
    }
}

public static int main (string[] args) {
    parse_args (args);

    Gtk.init ();
    Adw.init ();

    // All app infos
    all_app_infos = AppInfo.get_all ();
    AppInfoMonitor app_info_monitor = AppInfoMonitor.get ();
    app_info_monitor.changed.connect (() => {
        all_app_infos = AppInfo.get_all ();
    });

    foreign_helper = new WlrForeignHelper ();

#if USE_GLOBAL_GSCHEMA
    // Use the global compiled gschema in /usr/share/glib-2.0/schemas/*
    self_settings = new Settings ("org.erikreider.waydock");
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
        if (schema == null) {
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
                                   ApplicationFlags.DEFAULT_FLAGS);

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
