class IconState : Object {
    public string app_id;
    public bool pinned;

    public List<Toplevel *> toplevels;

    public signal void refresh ();
    public signal void toplevel_added (Toplevel * toplevel);

    public IconState (string app_id, bool pinned) {
        this.app_id = app_id;
        this.pinned = pinned;
        this.toplevels = new List<Toplevel *> ();
    }

    public void move_to_front (Toplevel * toplevel) {
        toplevels.remove (toplevel);
        toplevels.insert (toplevel, 0);
    }

    public void add_toplevel (Toplevel * toplevel) {
        toplevels.append (toplevel);
        toplevel_added (toplevel);
    }

    /// Returns true if there are no toplevels left
    public bool remove_toplevel (owned Toplevel toplevel) {
        toplevels.remove (toplevel);
        refresh ();
        return toplevels.is_empty ();
    }
}

class Icon : Gtk.Box {
    public unowned IconState ? state { get; private set; default = null; }
    public DesktopAppInfo ? app_info;

    private string app_name;

    Gtk.GestureClick gesture_click;

    private Gtk.Image image;
    private Gtk.Box num_open_box;

    public Icon () {
        Object (orientation : Gtk.Orientation.VERTICAL, spacing : 4);

        add_css_class ("dock-icon");

        image = new Gtk.Image ();
        append (image);

        num_open_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
        num_open_box.set_halign (Gtk.Align.CENTER);
        num_open_box.add_css_class ("num_open_box");
        append (num_open_box);
    }

    public void init (IconState id) {
        this.state = id;
        this.app_name = id.app_id;

        app_info = get_app_info (id.app_id);

        gesture_click = new Gtk.GestureClick ();
        gesture_click.set_button (0);
        gesture_click.released.connect (click_listener);
        add_controller (gesture_click);

        set_image_icon_from_app_info (app_info, id.app_id, image);

        listen_to_signals ();

        refresh ();
    }

    public void listen_to_signals () {
        state.refresh.connect (refresh);
        state.toplevel_added.connect (toplevel_added);
    }

    public void disconnect_from_signals () {
        state.refresh.disconnect (refresh);
        state.toplevel_added.disconnect (toplevel_added);
    }

    private void click_listener () {
        uint button = gesture_click.get_current_button ();
        if (button <= 0) {
            warning ("Button: %u pressed, ignoring...", button);
            return;
        }
        switch (button) {
            case 1:
                left_click ();
                break;
            case 2:
                middle_click ();
                break;
            case 3:
                right_click ();
                break;
            default:
                break;
        }
    }

    private void show_popover () {
        DockPopover popover = new DockPopover (this);

        unowned Window window = (Window) get_root ();
        popover.set_parent (window);

        Graphene.Point out_point;
        Graphene.Point point = { get_width () / 2, 0, };
        compute_point (window, point, out out_point);
        var rect = Gdk.Rectangle () {
            x = (int) out_point.x,
            y = 0,
        };
        popover.set_pointing_to (rect);

        popover.set_position (Gtk.PositionType.TOP);

        popover.popup ();
    }

    private void detach_child () {
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

    private void launch_application () {
        if (app_info == null) {
            return;
        }
        try {
            string[] spawn_env = Environ.get ();
            string[] argvp = {};
            Shell.parse_argv (app_info.get_commandline (), out argvp);
            Pid pid;

            Process.spawn_async (
                null,
                argvp,
                spawn_env,
                SpawnFlags.SEARCH_PATH_FROM_ENVP | SpawnFlags.SEARCH_PATH,
                detach_child,
                out pid);
        } catch (Error e) {
            error ("Launch error: %s", e.message);
        }
    }

    private void left_click () {
        // Check if only there's only 1 item
        uint length = state.toplevels.length ();
        if (length == 0) {
            launch_application ();
        } else if (length == 1) {
            WlrForeignHelper.activate_toplevel (state.toplevels.nth_data (0));
        } else {
            // Show window picker popover
            show_popover ();
        }
    }

    private void middle_click () {
        launch_application ();
    }

    private void right_click () {
        // TODO: Right click
    }

    private void refresh_name () {
        if (app_info != null) {
            app_name = app_info.get_display_name ();
        } else {
            unowned var link = state.toplevels.first ();
            if (link != null && link.data != null && link.data->title != null) {
                app_name = link.data->title;
            } else {
                app_name = state.app_id;
            }
        }
    }

    private void set_tooltip () {
        if (state.toplevels.length () <= 1) {
            set_tooltip_text (app_name);
        } else {
            set_tooltip_text ("%s - %u".printf (app_name, state.toplevels.length ()));
        }
    }

    private void set_running_circles () {
        // Clear all previous
        unowned Gtk.Widget widget = num_open_box.get_first_child ();
        while ((widget = num_open_box.get_first_child ()) != null) {
            num_open_box.remove (widget);
        }

        uint length = state.toplevels.length ().clamp (0, 3);
        for (uint i = 0; i < length; i++) {
            Adw.Bin circle = new Adw.Bin ();
            circle.add_css_class ("circle");
            num_open_box.append (circle);
        }
    }

    public void refresh () {
        refresh_name ();
        set_running_circles ();
        // TODO: Popover tooltips instead to always make them appear above the dock
        set_tooltip ();
    }

    public void toplevel_added (Toplevel * toplevel) {
        if (state != null && state.app_id == null) {
            state.app_id = toplevel->app_id;
        }
        assert (state != null && toplevel->app_id == state.app_id);

        refresh ();
    }
}
