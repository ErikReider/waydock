public class Window : Gtk.ApplicationWindow, Gtk.Orientable {
    private DockList list;

    public unowned Gdk.Monitor monitor { get; construct set; }

    public Direction orientation_direction { get; set; default = Direction.START; }
    public Gtk.Orientation orientation { get; set; default = Gtk.Orientation.VERTICAL; }
    public Gtk.Orientation opposite_orientation {
        get {
            switch (orientation) {
                case Gtk.Orientation.VERTICAL:
                    return Gtk.Orientation.HORIZONTAL;
                default:
                case Gtk.Orientation.HORIZONTAL:
                    return Gtk.Orientation.VERTICAL;
            }
        }
    }

    public bool minimized { get; private set; default = false; }
    Gtk.EventControllerMotion motion_controller;

    double _animation_progress = 0.0;
    internal double animation_progress {
        get {
            return _animation_progress;
        }
        set {
            _animation_progress = value;
            queue_resize ();
            // Delay the refresh until the above resize has been completed
            Idle.add_once (refresh_anchor);
        }
    }
    Adw.TimedAnimation animation;

    uint enter_timeout_id = 0;
    uint leave_timeout_id = 0;

    public bool dragging_and_dropping { get; set; default = false; }
    public int popovers_open { get; set; default = 0; }

    // TODO: Parse ~/.config/monitors.xml for primary output
    public Window (Gtk.Application app, Gdk.Monitor monitor) {
        Object (
            application: app,
            monitor: monitor,
            overflow: Gtk.Overflow.HIDDEN
        );

        // Layer shell
        GtkLayerShell.init_for_window (this);
        GtkLayerShell.set_layer (this, GtkLayerShell.Layer.TOP);
        GtkLayerShell.set_namespace (this, "waydock");
        GtkLayerShell.set_monitor (this, monitor);

        set_halign (Gtk.Align.FILL);
        set_valign (Gtk.Align.FILL);

        self_settings.changed.connect (settings_changed);

        list = new DockList (this);
        set_child (list);

        Adw.PropertyAnimationTarget animation_target
            = new Adw.PropertyAnimationTarget (this, "animation-progress");
        animation = new Adw.TimedAnimation (this, 0.0, 1.0, Constants.ANIMATION_DURATION,
                                            animation_target);
        animation.done.connect (refresh_anchor);

        notify["dragging-and-dropping"].connect (update_motion_controller_state);
        notify["popovers-open"].connect (update_motion_controller_state);

        motion_controller = new Gtk.EventControllerMotion ();
        ((Gtk.Widget) this).add_controller (motion_controller);
        motion_controller.motion.connect ((x, y) => {
            remove_timeout (ref leave_timeout_id);
        });
        motion_controller.enter.connect ((event) => {
            remove_timeout (ref leave_timeout_id);
            if (enter_timeout_id > 0 || animation.state == Adw.AnimationState.PLAYING) {
                return;
            }
            enter_timeout_id = Timeout.add_once (Constants.REVEAL_PRESSURE, () => {
                enter_timeout_id = 0;
                remove_timeout (ref leave_timeout_id);
                lock (animation) {
                    if (animation_progress >= 1.0) {
                        refresh_anchor ();
                        return;
                    }
                    animation.pause ();
                    animation.value_to = 1.0;
                    animation.value_from = animation_progress;
                    animation.play ();
                }
            });
        });
        motion_controller.leave.connect (() => add_leave_timeout (Constants.DISMISS_TIMEOUT));

        set_position ();
        set_minimized_value ();
    }

    private void remove_timeout (ref uint id) {
        if (id > 0) {
            Source.remove (id);
            id = 0;
        }
    }

    private void add_leave_timeout (uint custom_timeout) {
        // Disable hiding when disabled, like when dragging and dropping
        if (motion_controller.propagation_phase == Gtk.PropagationPhase.NONE) {
            return;
        }

        remove_timeout (ref enter_timeout_id);
        if (leave_timeout_id > 0) {
            return;
        }
        leave_timeout_id = Timeout.add_once (custom_timeout, () => {
            leave_timeout_id = 0;
            remove_timeout (ref enter_timeout_id);
            lock (animation) {
                if (animation_progress <= 0.0) {
                    refresh_anchor ();
                    return;
                }
                animation.pause ();
                animation.value_to = 0.0;
                animation.value_from = animation_progress;
                animation.play ();
            }
        });
    }

    private void settings_changed (string name) {
        switch (name) {
            case "position":
                set_position ();
                break;
            case "pinned":
                // TODO:
                break;
            case "minimized":
                set_minimized_value ();
                break;
            default:
                break;
        }
    }

    private void refresh_anchor () {
        switch (orientation) {
            case Gtk.Orientation.HORIZONTAL:
                switch (orientation_direction) {
                    case Direction.START:
                        GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, true);
                        GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, false);
                        GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, true);
                        GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, true);
                        break;
                    case Direction.END:
                    case Direction.NONE:
                        GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, false);
                        GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, true);
                        GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, true);
                        GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, true);
                        break;
                }
                break;
            case Gtk.Orientation.VERTICAL:
                switch (orientation_direction) {
                    case Direction.START:
                    case Direction.NONE:
                        GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, true);
                        GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, true);
                        GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, true);
                        GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, false);
                        break;
                    case Direction.END:
                        GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, true);
                        GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, true);
                        GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, false);
                        GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, true);
                        break;
                }
                break;
        }

        if (minimized) {
            // HACK: Force a size update by setting the auto exclusive zone
            GtkLayerShell.auto_exclusive_zone_enable (this);
            GtkLayerShell.set_exclusive_zone (this, Constants.MINIMIZED_SIZE);
        } else {
            GtkLayerShell.set_exclusive_zone (this, 0);
            GtkLayerShell.auto_exclusive_zone_enable (this);
        }
    }

    private void update_motion_controller_state () {
        popovers_open = int.max (popovers_open, 0);

        bool motion_enabled = minimized && !dragging_and_dropping && popovers_open == 0;
        motion_controller.set_propagation_phase (
            motion_enabled ? Gtk.PropagationPhase.CAPTURE : Gtk.PropagationPhase.NONE);
        add_leave_timeout (Constants.DISMISS_LONG_TIMEOUT);
    }

    private void set_minimized_value () {
        minimized = self_settings.get_boolean ("minimized");

        if (minimized) {
            if (!has_css_class ("minimized")) {
                add_css_class ("minimized");
            }
        } else {
            remove_css_class ("minimized");
        }

        update_motion_controller_state ();

        // Reset the state
        remove_timeout (ref leave_timeout_id);
        remove_timeout (ref enter_timeout_id);
        animation.pause ();
        animation_progress = (int) (!minimized);

        refresh_anchor ();
        queue_resize ();
    }

    private void set_position () {
        switch ((Position) self_settings.get_enum ("position")) {
            case Position.TOP:
                orientation = Gtk.Orientation.HORIZONTAL;
                orientation_direction = Direction.START;
                break;
            case Position.LEFT:
                orientation = Gtk.Orientation.VERTICAL;
                orientation_direction = Direction.START;
                break;
            case Position.RIGHT:
                orientation = Gtk.Orientation.VERTICAL;
                orientation_direction = Direction.END;
                break;
            case Position.BOTTOM:
                orientation = Gtk.Orientation.HORIZONTAL;
                orientation_direction = Direction.END;
                break;
        }

        list.set_orientation (orientation);
        list.set_halign (Gtk.Align.CENTER);
        list.set_valign (Gtk.Align.CENTER);

        list.remove_css_class ("vertical");
        list.remove_css_class ("horizontal");
        list.remove_css_class ("start");
        list.remove_css_class ("end");
        switch (orientation) {
            case Gtk.Orientation.HORIZONTAL:
                list.add_css_class ("horizontal");
                switch (orientation_direction) {
                    case Direction.START:
                        list.add_css_class ("start");
                        break;
                    case Direction.END:
                    case Direction.NONE:
                        list.add_css_class ("end");
                        break;
                }
                break;
            case Gtk.Orientation.VERTICAL:
                list.add_css_class ("vertical");
                switch (orientation_direction) {
                    case Direction.START:
                    case Direction.NONE:
                        list.add_css_class ("start");
                        break;
                    case Direction.END:
                        list.add_css_class ("end");
                        break;
                }
                break;
        }

        refresh_anchor ();

        // TODO: Resize all the icons to fit the width/height (shrink)
        list.refresh_items ();
    }

    protected override void size_allocate (int width, int height, int baseline) {
        if (minimized) {
            int new_width = width, new_height = height;
            switch (orientation) {
                case Gtk.Orientation.HORIZONTAL:
                    child.measure (Gtk.Orientation.VERTICAL, width,
                                   null, out new_height, null, null);
                    break;
                case Gtk.Orientation.VERTICAL:
                    child.measure (Gtk.Orientation.HORIZONTAL, height,
                                   null, out new_width, null, null);
                    break;
            }
            base.size_allocate (new_width, new_height, baseline);
        } else {
            base.size_allocate (width, height, baseline);
        }

        // Set the input region to only be the size of the actual dock
        Graphene.Rect bounds;
        if (list.compute_bounds (this, out bounds)) {
            unowned Gdk.Surface ?surface = get_surface ();
            if (surface == null) {
                return;
            }

            Cairo.RectangleInt rect = Cairo.RectangleInt () {
                x = (int) bounds.get_x (),
                y = (int) bounds.get_y (),
                width = (int) bounds.get_width (),
                height = (int) bounds.get_height (),
            };
            // Make sure that the input region includes the whole
            // horizontal/vertical "height"
            switch (orientation) {
                case Gtk.Orientation.HORIZONTAL :
                    rect.height = height;
                    break;
                case Gtk.Orientation.VERTICAL:
                    rect.width = width;
                    break;
            }
            Cairo.Region region = new Cairo.Region.rectangle (rect);
            surface.set_input_region (region);
        }
    }

    protected override void measure (Gtk.Orientation orientation, int for_size,
                                     out int minimum, out int natural,
                                     out int minimum_baseline, out int natural_baseline) {
        minimum_baseline = -1;
        natural_baseline = -1;

        child.measure (orientation, for_size,
                       out minimum, out natural, null, null);

        if (orientation == opposite_orientation && minimized) {
            minimum = (int) Adw.lerp (Constants.MINIMIZED_SIZE, minimum, animation_progress);
            natural = (int) Adw.lerp (Constants.MINIMIZED_SIZE, natural, animation_progress);
        }
    }

    protected override void snapshot (Gtk.Snapshot snapshot) {
        if (minimized) {
            snapshot.push_opacity (animation_progress);
        }

        base.snapshot (snapshot);

        if (minimized) {
            snapshot.pop ();
        }
    }

    public void debug_print_list_store () {
        icons_list.debug_print_list_store ();
    }
}
