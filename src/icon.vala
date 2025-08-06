public class Icon : Gtk.Box {
    public unowned IconState ? state { get; private set; default = null; }
    public DesktopAppInfo ? app_info;
    private KeyFile ? keyfile;

    private string app_name;

    Gtk.GestureClick gesture_click;

    private Gtk.Image image { get; private set; }
    private Gtk.Box num_open_box;

    private unowned Window window;

    public int pixel_size {
        get { return image.pixel_size; }
    }

    public Icon (Window window) {
        Object (
            orientation: window.opposite_orientation,
            spacing: 4
        );
        this.window = window;

        add_css_class ("dock-icon");

        image = new Gtk.Image ();
        // TODO: Make configurable
        image.set_pixel_size (48);
        image.add_css_class ("icon-image");
        append (image);

        num_open_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
        num_open_box.set_halign (Gtk.Align.CENTER);
        num_open_box.set_valign (Gtk.Align.CENTER);
        num_open_box.add_css_class ("num_open_box");
        append (num_open_box);
    }

    public void init (IconState state) {
        this.state = state;
        this.app_name = state.app_id;

        state.notify["focused"].connect (() => {
            if (state.focused) {
                add_css_class ("focused");
            } else {
                remove_css_class ("focused");
            }
        });

        if (state.minimized) {
            add_css_class ("minimized");
        }

        // TODO: Check if other icon has same app_info
        // (ex: gtk4-demo and gtk4-demo fishbowl demo share the same desktop file)
        app_info = get_app_info (state.app_id);
        if (app_info != null) {
            keyfile = new KeyFile ();
            try {
                keyfile.load_from_file (app_info.get_filename (), KeyFileFlags.NONE);
            } catch (Error e) {
                warning ("Could not load KeyFile for: %s", state.app_id);
                keyfile = null;
            }
        }

        gesture_click = new Gtk.GestureClick ();
        gesture_click.set_button (0);
        gesture_click.released.connect (click_listener);
        add_controller (gesture_click);

        set_image_icon_from_app_info (app_info, state.app_id, image);

        listen_to_signals ();

        refresh ();
    }

    public inline Gdk.Paintable get_paintable () {
        return get_paintable_from_app_info (app_info,
                                            state.app_id,
                                            image.pixel_size,
                                            get_scale_factor ());
    }

    public void listen_to_signals () {
        state.refresh.connect (refresh);
        state.toplevel_added.connect (toplevel_added);
    }

    public void disconnect_from_signals () {
        state.refresh.disconnect (refresh);
        state.toplevel_added.disconnect (toplevel_added);
    }

    private void click_listener (int n_press, double x, double y) {
        if (x < 0 || x > get_width () || y < 0 || y > get_height ()) {
            return;
        }

        uint button = gesture_click.get_current_button ();
        if (button <= 0) {
            debug ("Button: %u pressed, ignoring...", button);
            return;
        }
        switch (button) {
            case Gdk.BUTTON_PRIMARY :
                left_click ();
                break;
            case Gdk.BUTTON_MIDDLE :
                middle_click ();
                break;
            case Gdk.BUTTON_SECONDARY:
                right_click ();
                break;
            default:
                break;
        }
    }

    private void show_popover (Gtk.Popover popover) {
        unowned Window window = (Window) get_root ();
        popover.set_parent (window);

        Graphene.Point out_point;
        compute_point (window, Graphene.Point.zero (), out out_point);
        var rect = Gdk.Rectangle () {
            x = (int) out_point.x,
            y = (int) out_point.y,
            width = get_width (),
            height = get_height (),
        };
        popover.set_pointing_to (rect);

        switch (window.orientation) {
        case Gtk.Orientation.HORIZONTAL:
            switch (window.orientation_direction) {
            case Direction.START:
                popover.set_position (Gtk.PositionType.BOTTOM);
                break;
            case Direction.END:
            case Direction.NONE:
                popover.set_position (Gtk.PositionType.TOP);
                break;
            }
            break;
        case Gtk.Orientation.VERTICAL:
            switch (window.orientation_direction) {
            case Direction.START:
            case Direction.NONE:
                popover.set_position (Gtk.PositionType.RIGHT);
                break;
            case Direction.END:
                popover.set_position (Gtk.PositionType.LEFT);
                break;
            }
            break;
        }

        popover.popup ();
    }

    private void left_click () {
        // Check if only there's only 1 item
        uint length = state.toplevels.length ();
        if (length == 0) {
            launch_application (state.app_id, app_info, keyfile, null);
        } else if (length == 1) {
            WlrForeignHelper.activate_toplevel (state.toplevels.nth_data (0));
        } else {
            // Show window picker popover
            DockPopover popover = new DockPopover (this);
            show_popover (popover);
        }
    }

    private void middle_click () {
        launch_application (state.app_id, app_info, keyfile, null);
    }

    private void right_click () {
        Menu menu = new Menu ();
        bool has_actions = false;

        // App Actions
        Menu app_section = new Menu ();
        SimpleActionGroup app_actions = new SimpleActionGroup ();
        foreach (var action in app_info.list_actions ()) {
            has_actions = true;

            MenuItem item = new MenuItem (
                app_info.get_action_name (action), "menu_toplevel.%s".printf (action));
            app_section.append_item (item);

            SimpleAction simple_action = new SimpleAction (action, null);
            simple_action.activate.connect (() => {
                launch_application (state.app_id, app_info, keyfile, action);
            });
            app_actions.add_action (simple_action);
        }
        menu.append_section (null, app_section);

        // Constant Actions
        Menu main_section = new Menu ();
        SimpleActionGroup actions = new SimpleActionGroup ();
        if (!has_actions) {
            main_section.append ("New Instance", "menu.new_instance");
            SimpleAction simple_action = new SimpleAction ("new_instance", null);
            simple_action.activate.connect (() => {
                launch_application (state.app_id, app_info, keyfile, null);
            });
            actions.add_action (simple_action);
        }
        if (state.pinned) {
            main_section.append ("Unpin from Dock", "menu.unpin");
            SimpleAction simple_action = new SimpleAction ("unpin", null);
            simple_action.activate.connect (() => {
                pinnedList.remove_pinned (state.app_id);
            });
            actions.add_action (simple_action);
        } else if (app_info != null) {
            main_section.append ("Pin to Dock", "menu.pin");
            SimpleAction simple_action = new SimpleAction ("pin", null);
            simple_action.activate.connect (() => {
                pinnedList.add_pinned (state.app_id);
            });
            actions.add_action (simple_action);
        }
        if (state.toplevels.nth (0) != null) {
            string text = state.toplevels.nth (1) != null ? "Close All" : "Close";
            main_section.append (text, "menu.close");
            SimpleAction simple_action = new SimpleAction ("close", null);
            simple_action.activate.connect (() => {
                foreach (var toplevel in state.toplevels) {
                    if (toplevel != null && toplevel.handle != null) {
                        toplevel.handle.close ();
                    }
                }
            });
            actions.add_action (simple_action);
        }
        menu.append_section (null, main_section);

        // Create the GTK Popover
        Gtk.PopoverMenu popover = new Gtk.PopoverMenu.from_model (menu);
        Gtk.ScrolledWindow scroll = (Gtk.ScrolledWindow) popover.child;
        scroll.set_min_content_height (-1);
        scroll.set_max_content_height (500);
        scroll.set_propagate_natural_height (true);
        popover.child.width_request = 200;

        popover.insert_action_group ("menu_toplevel", app_actions);
        popover.insert_action_group ("menu", actions);

        show_popover (popover);
    }

    private void refresh_name () {
        if (app_info != null) {
            app_name = app_info.get_display_name ();
        } else {
            unowned var link = state.toplevels.first ();
            if (link != null && link.data != null && link.data.title != null) {
                app_name = link.data.title;
            } else {
                app_name = state.app_id ?? "Unknown";
            }
        }
    }

    private void set_tooltip () {
        if (state.minimized) {
            string app_name = state.app_id ?? "Unknown";
            unowned var link = state.toplevels.first ();
            if (link != null && link.data != null && link.data.title != null) {
                app_name = link.data.title;
            }
            set_tooltip_text (app_name);
        } else if (state.toplevels.length () <= 1) {
            set_tooltip_text (app_name);
        } else {
            set_tooltip_text ("%s - %u".printf (app_name, state.toplevels.length ()));
        }
    }

    private void set_running_circles () {
        if (state.minimized) {
            return;
        }

        num_open_box.set_orientation (window.orientation);

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
        set_orientation (window.opposite_orientation);

        refresh_name ();
        set_running_circles ();
        // TODO: Popover tooltips instead to always make them appear above the dock
        set_tooltip ();

        // Reposition the running circles depending on the window position to
        // ensure that the buttons always are closest to the monitor edge.
        switch (window.orientation_direction) {
        case Direction.START:
            reorder_child_after (num_open_box, null);
            break;
        case Direction.NONE:
        case Direction.END:
            reorder_child_after (num_open_box, image);
            break;
        }
    }

    public void toplevel_added (Toplevel toplevel) {
        if (state != null && state.app_id == null) {
            state.app_id = toplevel.app_id;
        }
        assert (state != null && toplevel.app_id == state.app_id);

        refresh ();
    }
}
