class Icon : Gtk.Box {
    public List<Toplevel *> toplevels = new List<Toplevel *> ();
    public string ? app_id { get; private set; default = null; }
    public DesktopAppInfo ? app_info;
    public bool pinned = false;

    Gtk.GestureClick gesture_click = new Gtk.GestureClick ();

    Gtk.Box num_open_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);

    public Icon (string app_id) {
        Object (orientation : Gtk.Orientation.VERTICAL, spacing: 4);

        this.app_id = app_id;

        app_info = get_app_info (app_id);

        add_css_class ("dock-icon");

        gesture_click.pressed.connect (() => {
            // Check if only there's only 1 item
            uint length = toplevels.length ();
            if (length == 0) {
                try {
                    app_info.launch (null, new AppLaunchContext ());
                } catch (Error e) {
                    error ("Launch error: %s", e.message);
                }
            } else if (length == 1) {
                WlrForeignHelper.activate_toplevel (toplevels.nth_data (0));
            } else {
                // Show window picker popover
                show_popover ();
            }
        });
        add_controller (gesture_click);

        Gtk.Image image = new Gtk.Image ();
        set_image_icon_from_app_info (app_info, app_id, image);
        append (image);

        num_open_box.set_halign (Gtk.Align.CENTER);
        num_open_box.add_css_class ("num_open_box");
        append (num_open_box);

        // TODO: Popover tooltips instead to always make them appear above the dock
        set_tooltip ();
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

    private void set_tooltip () {
        string name = app_id;
        if (app_info != null) {
            name = app_info.get_display_name ();
        }

        if (toplevels.length () <= 1) {
            set_tooltip_text (name);
        } else {
            set_tooltip_text ("%s - %u".printf (name, toplevels.length ()));
        }
    }

    private void set_running_circles () {
        // Clear all previous
        unowned Gtk.Widget widget = num_open_box.get_first_child ();
        while ((widget = num_open_box.get_first_child ()) != null) {
            num_open_box.remove (widget);
        }

        uint length = toplevels.length ().clamp (0, 3);
        for (uint i = 0; i < length; i++) {
            Adw.Bin circle = new Adw.Bin ();
            circle.add_css_class ("circle");
            num_open_box.append (circle);
        }
    }

    public void add_toplevel (Toplevel * toplevel) {
        toplevels.append (toplevel);
        if (app_id == null) {
            app_id = toplevel->app_id;
        }
        assert (app_id != null && toplevel->app_id == app_id);

        set_running_circles ();
        set_tooltip ();
    }

    /// Returns true if there are no toplevels left
    public bool remove_toplevel (owned Toplevel toplevel) {
        toplevels.remove (toplevel);
        set_running_circles ();
        return toplevels.is_empty ();
    }
}


