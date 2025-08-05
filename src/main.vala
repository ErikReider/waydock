public enum direction {
    START = 0,
    END = 1,
    NONE = 2;
}

static Settings self_settings;

static PinnedList pinnedList;
static SortedListStore list_object;
static WlrForeignHelper foreign_helper;

static List<AppInfo> all_app_infos;

static bool activated = false;
static Gtk.Application app;

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

#if USE_GLOBAL_GSCHEMA
    // Use the global compiled gschema in /usr/share/glib-2.0/schemas/*
    self_settings = new Settings ("org.erikreider.waydock");
#else
    message ("Using local GSchema");
    // Meant for use in development.
    // Uses the compiled gschema in waydock/data/
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

    foreign_helper = new WlrForeignHelper ();
    pinnedList = new PinnedList ();
    list_object = new SortedListStore ();

    // Load custom CSS
    Gtk.CssProvider css_provider = new Gtk.CssProvider ();
    css_provider.load_from_resource (
        "/org/erikreider/waydock/style.css");
    Gtk.StyleContext.add_provider_for_display (
        Gdk.Display.get_default (),
        css_provider,
        Gtk.STYLE_PROVIDER_PRIORITY_USER);

    app = new Gtk.Application ("org.erikreider.waydock",
                                   ApplicationFlags.DEFAULT_FLAGS
                                   | ApplicationFlags.ALLOW_REPLACEMENT
                                   | ApplicationFlags.REPLACE);

    app.activate.connect (() => {
        if (activated) return;
        activated = true;
        init ();
        foreign_helper.start ();
    });

    return app.run ();
}

private static void init () {
    Gdk.Display ? display = Gdk.Display.get_default ();
    if (display == null) return;

    unowned ListModel monitors = display.get_monitors ();
    monitors.items_changed.connect (() => {
        init_windows (monitors);
    });

    init_windows (monitors);
}

private static void close_all_windows () {
    foreach (var window in app.get_windows ()) {
        window.close ();
    }
}

private static void add_window (Gdk.Monitor monitor) {
    Window win = new Window (app, monitor);
    win.present ();
}

private static void init_windows (ListModel monitors) {
    close_all_windows ();

    for (int i = 0; i < monitors.get_n_items (); i++) {
        Object ? obj = monitors.get_item (i);
        if (obj == null || !(obj is Gdk.Monitor)) continue;
        Gdk.Monitor monitor = (Gdk.Monitor) obj;
        add_window (monitor);
    }
}
