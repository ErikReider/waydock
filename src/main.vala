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

static unowned Gdk.Wayland.Display display;
static unowned Gdk.Wayland.Seat seat;
static unowned Wl.Display wl_display;
static unowned Wl.Seat wl_seat;
static Settings self_settings;

static PinnedList pinned_list;
static IconStateListStore icons_list;
static WlrForeignHelper foreign_helper;
static UnityService unity_service;

public class WaydockApp : Gtk.Application {
    private unowned ListModel monitors;
    private ListStore windows = new ListStore (typeof (Window));

    public WaydockApp () {
        Object (
            application_id: "org.erikreider.waydock",
            flags: ApplicationFlags.DEFAULT_FLAGS
            | ApplicationFlags.IS_SERVICE
            | ApplicationFlags.ALLOW_REPLACEMENT
            | ApplicationFlags.REPLACE
        );
    }

    public override void startup () {
        base.startup ();
        hold ();

        monitors = display.get_monitors ();
        monitors.items_changed.connect (monitors_changed);
        monitors_changed (0, 0, monitors.get_n_items ());

        unity_service.start ();
        foreign_helper.start ();
    }

    private void monitors_changed (uint position, uint removed, uint added) {
        for (uint i = 0; i < removed; i++) {
            Window ?window = (Window ?) windows.get_item (position);
            window.close ();
            remove_window (window);
            windows.remove (position + i);
        }

        for (uint i = 0; i < added; i++) {
            Gdk.Monitor ?monitor = (Gdk.Monitor ?) monitors.get_item (position + i);

            Window win = new Window (this, monitor);
            windows.insert (position + i, win);
            win.present ();
        }
    }
}

public static int main (string[] args) {
    // Parse arguments
    try {
        bool show_version = false;
        OptionEntry[] entries = {
            {
                "version",
                'v',
                OptionFlags.NONE,
                OptionArg.NONE,
                ref show_version,
                null,
                null,
            }
        };
        OptionContext context = new OptionContext ();
        context.set_help_enabled (true);
        context.add_main_entries (entries, null);
        context.parse (ref args);

        if (show_version) {
            print ("%s\n", Constants.VERSION);
            return 0;
        }
    } catch (Error e) {
        printerr ("%s\n", e.message);
        return 1;
    }

    Gtk.init ();
    Adw.init ();

    unowned Gdk.Display ?gdk_display = Gdk.Display.get_default ();
    assert_nonnull (gdk_display);
    unowned Gdk.Seat ?gdk_seat = gdk_display.get_default_seat ();
    assert_nonnull (gdk_seat);
    if (!(gdk_display is Gdk.Wayland.Display)
        || !(gdk_seat is Gdk.Wayland.Seat)) {
        printerr ("Only supports Wayland!");
        return 1;
    }
    display = (Gdk.Wayland.Display) gdk_display;
    seat = (Gdk.Wayland.Seat) gdk_seat;
    wl_display = display.get_wl_display ();
    wl_seat = seat.get_wl_seat ();

    // When the built type is release:
    // - Use the global compiled gschema in /usr/share/glib-2.0/schemas/*
    // When the built type is debug:
    // - Use the locally compiled gschema in the build directory
    self_settings = new Settings ("org.erikreider.waydock");

    foreign_helper = new WlrForeignHelper ();
    unity_service = new UnityService ();
    pinned_list = new PinnedList ();
    icons_list = new IconStateListStore ();

    // Load CSS
    Gtk.CssProvider css_provider = new Gtk.CssProvider ();
    css_provider.load_from_resource (
        "/org/erikreider/waydock/style.css");
    Gtk.StyleContext.add_provider_for_display (
        display,
        css_provider,
        Gtk.STYLE_PROVIDER_PRIORITY_USER);

    return new WaydockApp ().run (args);
}
