class IconState : Object {
    public string ? app_id;
    public bool pinned;
    public bool minimized = false;

    public List<Toplevel *> toplevels;

    public signal void refresh ();
    public signal void toplevel_added (Toplevel * toplevel);

    public IconState (string ? app_id, bool pinned) {
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

    public Toplevel * get_first_toplevel () {
        unowned List<Toplevel *> first_link = toplevels.first ();
        if (first_link == null) {
            return null;
        }
        return first_link.data;
    }
}

class Icon : Gtk.Box {
    const string DND_LEFT_CLASS_NAME = "dnd-hover-left";
    const string DND_RIGHT_CLASS_NAME = "dnd-hover-right";

    public unowned IconState ? state { get; private set; default = null; }
    public DesktopAppInfo ? app_info;
    private KeyFile ? keyfile;

    private string app_name;

    Gtk.GestureClick gesture_click;
    Gtk.DragSource drag_source;
    Gtk.DropTarget drop_target;

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

        // TODO: Check if other icon has same app_info
        // (ex: gtk4-demo and gtk4-demo fishbowl demo share the same desktop file)
        app_info = get_app_info (id.app_id);
        if (app_info != null) {
            keyfile = new KeyFile ();
            try {
                keyfile.load_from_file (app_info.get_filename (), KeyFileFlags.NONE);
            } catch (Error e) {
                warning ("Could not load KeyFile for: %s", id.app_id);
                keyfile = null;
            }
        }

        gesture_click = new Gtk.GestureClick ();
        gesture_click.set_button (0);
        gesture_click.released.connect (click_listener);
        add_controller (gesture_click);

        // Drag Source
        drag_source = new Gtk.DragSource ();
        drag_source.set_actions (Gdk.DragAction.MOVE);
        drag_source.prepare.connect ((x, y) => {
            drag_source.set_icon (new Gtk.WidgetPaintable (image), (int) x, (int) y);

            Value drop_value = Value(typeof (IconState));
            drop_value.set_object (state);
            return new Gdk.ContentProvider.for_value (drop_value);
        });
        // Hide the docked icon until dnd end/cancel
        drag_source.drag_begin.connect(() => {
            this.set_opacity (0.0);
        });
        drag_source.drag_end.connect(() => {
            this.set_opacity (1.0);
        });
        drag_source.drag_cancel.connect(() => {
            this.set_opacity (1.0);
            return true;
        });
        add_controller (drag_source);

        // Drag Target
        drop_target = new Gtk.DropTarget (typeof(IconState), Gdk.DragAction.MOVE);
        drop_target.set_preload (true);
        add_controller (drop_target);
        drop_target.enter.connect (() => {
            reset_dnd_classes ();
            return Gdk.DragAction.MOVE;
        });
        drop_target.leave.connect (reset_dnd_classes);
        drop_target.motion.connect ((x, y) => {
            // Skip self
            Value ? value = drop_target.get_value ();
            if (value == null || !value.holds (typeof(IconState))
                || this.state == value.get_object ()) {
                return 0;
            }

            reset_dnd_classes ();
            int half_width = get_width () / 2;
            bool is_right = x > half_width;
            if (is_right) {
                add_css_class (DND_RIGHT_CLASS_NAME);
            } else {
                add_css_class (DND_LEFT_CLASS_NAME);
            }
            return Gdk.DragAction.MOVE;
        });
        drop_target.drop.connect ((value, x, y) => {
            if (!value.holds (typeof(IconState))) {
                warning ("Tried DND for invalid type: %s", value.type_name ());
            }
            unowned IconState drop_state = (IconState) value.get_object ();
            if (drop_state == null || drop_state == this.state) {
                return false;
            }

            int half_width = get_width () / 2;
            bool is_right = x > half_width;
            return pinnedList.dnd_drop (this.state, drop_state, is_right);
        });

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
            case Gdk.BUTTON_SECONDARY :
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
                    if (toplevel != null && toplevel->handle != null) {
                        toplevel->handle.close ();
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
            if (link != null && link.data != null && link.data->title != null) {
                app_name = link.data->title;
            } else {
                app_name = state.app_id ?? "Unknown";
            }
        }
    }

    private void set_tooltip () {
        if (state.minimized) {
            string app_name = state.app_id ?? "Unknown";
            unowned var link = state.toplevels.first ();
            if (link != null && link.data != null && link.data->title != null) {
                app_name = link.data->title;
            }
            set_tooltip_text (app_name);
        } else if (state.toplevels.length () <= 1) {
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

    private void reset_dnd_classes () {
        remove_css_class (DND_LEFT_CLASS_NAME);
        remove_css_class (DND_RIGHT_CLASS_NAME);
    }
}
