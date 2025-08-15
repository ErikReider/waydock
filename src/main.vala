public enum Direction {
    START = 0,
    END = 1,
    NONE = 2;
}
public enum Position {
    TOP = 0,
    LEFT = 1,
    RIGHT = 2,
    BOTTOM = 3;
}

static Settings self_settings;

static PinnedList pinnedList;
static SortedListStore list_object;
static WlrForeignHelper foreign_helper;

static List<AppInfo> all_app_infos;

static bool activated = false;
static Gtk.Application app;
static unowned ListModel monitors;
static ListStore windows;

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
        // TODO: Refresh all Toplevels and their IconStates
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
        app.hold ();
        init ();
        foreign_helper.start ();
    });

    return app.run ();
}

private static void init () {
    windows = new ListStore (typeof (Window));

    Gdk.Display ? display = Gdk.Display.get_default ();
    assert_nonnull (display);

    monitors = display.get_monitors ();
    monitors.items_changed.connect (monitors_changed);

    monitors_changed (0, 0, monitors.get_n_items ());
}

public static void remove_window (Window window) {
    for (uint i = 0; i < windows.get_n_items (); i++) {
        Window w = (Window) windows.get_item (i);
        if (w != window) {
            continue;
        }
        window.close ();
        app.remove_window (window);
        windows.remove (i);
        break;
    }
}

private static void monitors_changed (uint position, uint removed, uint added) {
    for (uint i = 0; i < removed; i++) {
        Window window = (Window) windows.get_item (position + i);
        window.close ();
        app.remove_window (window);
        windows.remove (position + i);
    }

    for (uint i = 0; i < added; i++) {
        Gdk.Monitor monitor = (Gdk.Monitor) monitors.get_item (position + i);

        Window win = new Window (app, monitor);
        windows.insert (position + i, win);
        win.present ();
    }
}
