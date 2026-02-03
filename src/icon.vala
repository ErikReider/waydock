public class Icon : Gtk.Box {
    public unowned IconState ?state { get; private set; default = null; }

    private string app_name;

    private int popovers_open = 0;

    Gtk.GestureClick gesture_click;
    Gtk.EventControllerMotion motion_controller;

    private IconTooltip tooltip_popover;

    private Gtk.Overlay overlay;
    private Gtk.Image image;
    private Gtk.ProgressBar progress_bar;
    private Gtk.Label count_badge;
    private Gtk.Box num_open_box;

    private unowned Window window;

    public int pixel_size {
        get {
            return image.pixel_size;
        }
    }

    construct {
        add_css_class ("dock-icon");

        tooltip_popover = new IconTooltip ();

        overlay = new Gtk.Overlay ();
        append (overlay);

        image = new Gtk.Image ();
        // TODO: Make configurable
        image.set_pixel_size (48);
        image.add_css_class ("icon-image");
        overlay.set_child (image);

        // Unity Launcher API Progressbar
        progress_bar = new Gtk.ProgressBar ();
        progress_bar.set_orientation (Gtk.Orientation.HORIZONTAL);
        progress_bar.set_can_target (false);
        progress_bar.set_valign (Gtk.Align.END);
        progress_bar.add_css_class ("progress-bar");
        overlay.add_overlay (progress_bar);

        // Unity Launcher API Count-Badge
        count_badge = new Gtk.Label ("0");
        count_badge.set_can_target (false);
        count_badge.set_valign (Gtk.Align.START);
        count_badge.set_halign (Gtk.Align.END);
        count_badge.set_justify (Gtk.Justification.CENTER);
        count_badge.set_single_line_mode (true);
        count_badge.add_css_class ("count-badge");
        overlay.add_overlay (count_badge);

        num_open_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
        num_open_box.set_halign (Gtk.Align.CENTER);
        num_open_box.set_valign (Gtk.Align.CENTER);
        num_open_box.add_css_class ("num_open_box");
        append (num_open_box);
    }

    public Icon (Window window) {
        Object (
            css_name: "dockicon",
            orientation : window.opposite_orientation,
            spacing: 4
        );
        this.window = window;
    }

    public void init (IconState state) {
        this.state = state;
        this.app_name = state.app_id;

        if (state.minimized) {
            add_css_class ("minimized");
        }

        gesture_click = new Gtk.GestureClick ();
        gesture_click.set_button (0);
        gesture_click.released.connect (click_listener);
        add_controller (gesture_click);

        motion_controller = new Gtk.EventControllerMotion ();
        motion_controller.enter.connect (show_tooltip);
        motion_controller.leave.connect (hide_tooltip);
        add_controller (motion_controller);

        listen_to_signals ();

        refresh ();
    }

    public inline Gdk.Paintable get_paintable () {
        return get_paintable_from_app_info (state.app_info,
                                            state.app_id,
                                            image.pixel_size,
                                            get_scale_factor ());
    }

    public void listen_to_signals () {
        state.refresh.connect (refresh);
        state.toplevel_added.connect (toplevel_added);
        state.notify["focused"].connect (focused_changed);
    }

    public void disconnect_from_signals () {
        state.refresh.disconnect (refresh);
        state.toplevel_added.disconnect (toplevel_added);
        state.notify["focused"].disconnect (focused_changed);
    }

    private void focused_changed () {
        if (state.focused) {
            add_css_class ("focused");
        } else {
            remove_css_class ("focused");
        }
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
            case Gdk.BUTTON_PRIMARY:
                left_click ();
                break;
            case Gdk.BUTTON_MIDDLE:
                middle_click ();
                break;
            case Gdk.BUTTON_SECONDARY:
                right_click ();
                break;
            default:
                break;
        }
    }

    private inline void position_popover (Gtk.Popover popover) {
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
    }

    private void show_popover (Gtk.Popover popover) {
        popovers_open++;
        window.popovers_open++;
        popover.unmap.connect (() => {
            popovers_open--;
            window.popovers_open--;
            // Make sure to try to show the tooltip again
            show_tooltip ();
        });
        popover.set_parent (this);

        position_popover (popover);

        popover.popup ();
    }

    private void left_click () {
        // Check if only there's only 1 item
        if (state.toplevels.is_empty ()) {
            launch_application (state.app_id, state.app_info, state.keyfile, null);
        } else if (state.only_single_toplevel ()) {
            WlrForeignHelper.activate_toplevel (state.toplevels.nth_data (0));
        } else {
            // Show window picker popover
            DockPopover popover = new DockPopover (this);
            show_popover (popover);
        }
    }

    private void middle_click () {
        launch_application (state.app_id, state.app_info, state.keyfile, null);
    }

    private void right_click () {
        Menu menu = new Menu ();
        bool has_actions = false;

        // App Actions
        Menu app_section = new Menu ();
        SimpleActionGroup app_actions = new SimpleActionGroup ();
        foreach (var action in state.app_info?.list_actions ()) {
            has_actions = true;

            MenuItem item = new MenuItem (
                state.app_info.get_action_name (action), "menu_toplevel.%s".printf (action));
            app_section.append_item (item);

            SimpleAction simple_action = new SimpleAction (action, null);
            simple_action.activate.connect (() => {
                launch_application (state.app_id, state.app_info, state.keyfile, action);
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
                launch_application (state.app_id, state.app_info, state.keyfile, null);
            });
            actions.add_action (simple_action);
        }
        if (state.pinned) {
            main_section.append ("Unpin from Dock", "menu.unpin");
            SimpleAction simple_action = new SimpleAction ("unpin", null);
            simple_action.activate.connect (() => {
                pinned_list.remove_pinned (state.app_id);
            });
            actions.add_action (simple_action);
        } else if (state.app_info != null) {
            main_section.append ("Pin to Dock", "menu.pin");
            SimpleAction simple_action = new SimpleAction ("pin", null);
            simple_action.activate.connect (() => {
                pinned_list.add_pinned (state.app_id);
            });
            actions.add_action (simple_action);
        }
        if (!state.toplevels.is_empty ()) {
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
        if (state.app_info != null) {
            app_name = state.app_info.get_display_name ();
            if (app_name != null) {
                return;
            }
        }
        unowned var link = state.toplevels.first ();
        if (link != null && link.data != null && link.data.title != null) {
            app_name = link.data.title;
        } else {
            app_name = state.app_id;
        }

        if (app_name == null) {
            app_name = "Unknown";
        }
    }

    private void update_tooltip () {
        if (state.minimized) {
            string text = app_name;
            unowned List<unowned Toplevel> ?link = state.toplevels.first ();
            if (link != null && link.data != null && link.data.title != null) {
                text = "%s\n%s".printf (app_name, link.data.title);
            }
            tooltip_popover.set_text (text);
        } else if (!state.multiple_toplevels ()) {
            tooltip_popover.set_text (app_name);
        } else {
            tooltip_popover.set_text ("%s - %u".printf (app_name, state.toplevels.length ()));
        }
        position_popover (tooltip_popover);
    }

    private void hide_tooltip () {
        tooltip_popover.popdown ();
        tooltip_popover.unparent ();
    }

    private void show_tooltip () {
        // Only display the tooltip if no other popover is visible
        if (!tooltip_popover.get_visible ()
            && popovers_open == 0
            && motion_controller.contains_pointer) {
            tooltip_popover.set_parent (this);
            position_popover (tooltip_popover);
            tooltip_popover.popup ();
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
        set_image_icon_from_app_info (state.app_info, state.app_id, image);

        set_orientation (window.opposite_orientation);

        if (state.launcher_entry != null) {
            unowned LauncherEntry entry = state.launcher_entry;
            progress_bar.set_visible (entry.progress_visible);
            count_badge.set_visible (entry.count_visible);

            progress_bar.set_fraction (entry.progress.clamp (0.0, 1.0));
            count_badge.set_text (entry.count.to_string ("%'d"));
        } else {
            progress_bar.set_visible (false);
            count_badge.set_visible (false);
        }

        refresh_name ();
        set_running_circles ();
        // TODO: Popover tooltips instead to always make them appear above the dock
        update_tooltip ();

        // Reposition the running circles depending on the window position to
        // ensure that the buttons always are closest to the monitor edge.
        switch (window.orientation_direction) {
            case Direction.START :
                reorder_child_after (num_open_box, null);
                break;
            case Direction.NONE :
            case Direction.END :
                reorder_child_after (num_open_box, overlay);
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
