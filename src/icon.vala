class Icon : Gtk.Box {
    public List<Toplevel *> toplevels = new List<Toplevel *> ();
    public string ? app_id { get; private set; default = null; }
    public DesktopAppInfo ? app_info;
    public bool pinned = false;

    private string app_name;

    Gtk.GestureClick gesture_click = new Gtk.GestureClick ();
    Gtk.Box num_open_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);

    public Icon (string app_id) {
        Object (orientation : Gtk.Orientation.VERTICAL, spacing: 4);

        this.app_id = app_id;
        this.app_name = app_id;

        app_info = get_app_info (app_id);

        add_css_class ("dock-icon");

        gesture_click.set_button (0);
        gesture_click.released.connect (() => {
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
            }
        });
        add_controller (gesture_click);

        Gtk.Image image = new Gtk.Image ();
        set_image_icon_from_app_info (app_info, app_id, image);
        append (image);

        num_open_box.set_halign (Gtk.Align.CENTER);
        num_open_box.add_css_class ("num_open_box");
        append (num_open_box);

        refresh ();
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

    private void launch_application () {
        if (app_info == null) {
            return;
        }
        try {
            app_info.launch (null, new AppLaunchContext ());
        } catch (Error e) {
            error ("Launch error: %s", e.message);
        }
    }

    private void left_click () {
        // Check if only there's only 1 item
        uint length = toplevels.length ();
        if (length == 0) {
            launch_application ();
        } else if (length == 1) {
            WlrForeignHelper.activate_toplevel (toplevels.nth_data (0));
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
            unowned var link = toplevels.first ();
            if (link != null && link.data != null && link.data->title != null) {
                app_name = link.data->title;
            } else {
                app_name = app_id;
            }
        }
    }

    private void set_tooltip () {
        if (toplevels.length () <= 1) {
            set_tooltip_text (app_name);
        } else {
            set_tooltip_text ("%s - %u".printf (app_name, toplevels.length ()));
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

    public void refresh () {
        refresh_name ();
        set_running_circles ();
        // TODO: Popover tooltips instead to always make them appear above the dock
        set_tooltip ();
    }

    public void add_toplevel (Toplevel * toplevel) {
        toplevels.append (toplevel);
        if (app_id == null) {
            app_id = toplevel->app_id;
        }
        assert (app_id != null && toplevel->app_id == app_id);

        refresh ();
    }

    public void move_to_front (Toplevel * toplevel) {
        toplevels.remove (toplevel);
        toplevels.insert (toplevel, 0);
    }

    /// Returns true if there are no toplevels left
    public bool remove_toplevel (owned Toplevel toplevel) {
        toplevels.remove (toplevel);
        refresh ();
        return toplevels.is_empty ();
    }
}
