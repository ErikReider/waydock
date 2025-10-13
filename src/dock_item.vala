public class DockItem : Gtk.Widget {
    const int TRANSITION_DURATION = 250;
    Direction drag_direction = Direction.NONE;

    unowned Window window;
    Icon icon;

    private double _start_animation_progress = 0.0;
    public double start_animation_progress {
        get {
            return _start_animation_progress;
        }
        set {
            _start_animation_progress = value;
            queue_resize ();
        }
    }
    private Adw.TimedAnimation start_animation;

    private double _end_animation_progress = 0.0;
    public double end_animation_progress {
        get {
            return _end_animation_progress;
        }
        set {
            _end_animation_progress = value;
            queue_resize ();
        }
    }
    private Adw.TimedAnimation end_animation;

    private Gtk.DragSource drag_source;
    private Gtk.DropTarget drop_target;

    construct {
        Adw.PropertyAnimationTarget start_target
            = new Adw.PropertyAnimationTarget (this, "start-animation-progress");
        start_animation = new Adw.TimedAnimation (this, 0.0, 0.0, TRANSITION_DURATION,
                                                  start_target);
        Adw.PropertyAnimationTarget end_target
            = new Adw.PropertyAnimationTarget (this, "end-animation-progress");
        end_animation = new Adw.TimedAnimation (this, 0.0, 0.0, TRANSITION_DURATION, end_target);
    }

    public DockItem (Window window) {
        Object (css_name: "dockitem");

        this.window = window;
        this.icon = new Icon (window);

        icon.set_parent (this);
    }

    public override void dispose () {
        icon.unparent ();

        base.dispose ();
    }

    protected override Gtk.SizeRequestMode get_request_mode () {
        return Gtk.SizeRequestMode.CONSTANT_SIZE;
    }

    protected override void measure (Gtk.Orientation orientation, int for_size,
                                     out int minimum, out int natural,
                                     out int minimum_baseline, out int natural_baseline) {
        minimum = 0;
        natural = 0;
        minimum_baseline = -1;
        natural_baseline = -1;

        int child_min, child_nat;

        if (!icon.visible) {
            return;
        }

        icon.measure (orientation, for_size,
                      out child_min, out child_nat, null, null);

        minimum = child_min;
        natural = child_nat;

        if (orientation != window.orientation) {
            return;
        }

        minimum += (int) (minimum * start_animation_progress + minimum * end_animation_progress);
        natural += (int) (natural * start_animation_progress + natural * end_animation_progress);
    }

    protected override void size_allocate (int width, int height, int baseline) {
        Gtk.Requisition child_req;
        icon.get_preferred_size (out child_req, null);

        int is_horizontal = (int) (window.orientation == Gtk.Orientation.HORIZONTAL);
        Gsk.Transform transform = new Gsk.Transform ()
             .translate (
            Graphene.Point ().init (
                (int) (child_req.width * start_animation_progress) * is_horizontal,
                (int) (child_req.height * start_animation_progress) * (1 - is_horizontal))
             );
        icon.allocate (child_req.width, child_req.height, -1, transform);
    }

    public inline void init (IconState state) {
        icon.init (state);
        init_dnd ();
    }

    public inline void refresh () {
        icon.refresh ();
    }

    private void set_drag_direction (Direction dir) {
        if (drag_direction == dir) {
            return;
        }
        drag_direction = dir;

        start_animation.pause ();
        end_animation.pause ();

        switch (dir) {
            case Direction.START:
                start_animation.value_to = 1.0;
                end_animation.value_to = 0.0;
                break;
            case Direction.END:
                start_animation.value_to = 0.0;
                end_animation.value_to = 1.0;
                break;
            case Direction.NONE:
                start_animation.value_to = 0.0;
                end_animation.value_to = 0.0;
                break;
        }
        start_animation.value_from = start_animation_progress;
        end_animation.value_from = end_animation_progress;
        start_animation.play ();
        end_animation.play ();
    }

    private void init_dnd () {
        // Don't support DND for minimized icons
        if (icon.state.minimized) {
            return;
        }

        // Drag Source
        drag_source = new Gtk.DragSource ();
        drag_source.set_actions (Gdk.DragAction.MOVE);
        add_controller (drag_source);
        drag_source.prepare.connect ((x, y) => {
            int scale = get_scale_factor ();
            int size = icon.pixel_size;

            drag_source.set_icon (icon.get_paintable (),
                                  size / (2 * scale),
                                  size / (2 * scale));

            Value drop_value = Value (typeof (IconState));
            drop_value.set_object (icon.state);
            return new Gdk.ContentProvider.for_value (drop_value);
        });
        // Hide the docked icon until dnd end/cancel
        drag_source.drag_begin.connect (() => {
            this.set_opacity (0.0);
        });
        drag_source.drag_end.connect (() => {
            this.set_opacity (1.0);
        });
        drag_source.drag_cancel.connect (() => {
            this.set_opacity (1.0);
            return true;
        });

        // Drop Target
        drop_target = new Gtk.DropTarget (typeof (IconState),
                                          Gdk.DragAction.MOVE);
        drop_target.set_preload (true);
        add_controller (drop_target);
        drop_target.leave.connect (() => set_drag_direction (Direction.NONE));
        drop_target.enter.connect (calculate_dnd_direction);
        drop_target.motion.connect (calculate_dnd_direction);
        drop_target.drop.connect ((value, x, y) => {
            if (!value.holds (typeof (IconState))) {
                warning ("Tried DND for invalid type: %s", value.type_name ());
            }
            unowned IconState drop_state = (IconState) value.get_object ();
            if (drop_state == null || drop_state == icon.state) {
                return false;
            }

            Direction dir;
            if (window.orientation == Gtk.Orientation.HORIZONTAL) {
                int half_width = get_width () / 2;
                dir = x > half_width ? Direction.END : Direction.START;
            } else {
                int half_height = get_height () / 2;
                dir = y > half_height ? Direction.END : Direction.START;
            }
            bool result = false;
            if (drop_state.pinned || icon.state.pinned) {
                result |= pinned_list.dnd_drop (icon.state, drop_state, dir);
            }
            if (!icon.state.pinned) {
                // Reposition icon (includes pinned -> unpinned dnd)
                result |= drop_state.request_icon_reposition (icon.state, dir);
            }
            return result;
        });
    }

    private Direction icon_is_adjacent (IconState reference, IconState sibling) {
        if (reference == null || sibling == null || reference == sibling
            || reference.pinned != sibling.pinned) {
            return Direction.NONE;
        }

        uint ref_pos;
        if (!icons_list.find_sorted (reference, out ref_pos)) {
            debug ("Could not find reference icon state in List Store");
            return Direction.NONE;
        }

        if (ref_pos - 1 >= 0) {
            IconState ?state = icons_list.get_item_sorted (ref_pos - 1);
            if (state != null && state == sibling) {
                return Direction.START;
            }
        }
        if (ref_pos + 1 < icons_list.get_n_items ()) {
            IconState ?state = icons_list.get_item_sorted (ref_pos + 1);
            if (state != null && state == sibling) {
                return Direction.END;
            }
        }

        return Direction.NONE;
    }

    private Gdk.DragAction calculate_dnd_direction (Gtk.DropTarget drop_target,
                                                    double x, double y) {
        // Skip self
        Value ?value = drop_target.get_value ();
        if (value == null || !value.holds (typeof (IconState))
            || icon.state == value.get_object ()) {
            return 0;
        }
        IconState drag_state = (IconState) value.get_object ();

        Direction adjacent = icon_is_adjacent (icon.state, drag_state);

        Direction dir;
        if (window.orientation == Gtk.Orientation.HORIZONTAL) {
            int half_width = get_width () / 2;
            dir = x > half_width ? Direction.END : Direction.START;
        } else {
            int half_height = get_height () / 2;
            dir = y > half_height ? Direction.END : Direction.START;
        }

        // Ignore setting padding offset when it's the neighbouring icon
        bool is_adjacent = adjacent != Direction.NONE && dir == adjacent;
        if (dir == Direction.END && !is_adjacent) {
            set_drag_direction (Direction.END);
        } else if (dir == Direction.START && !is_adjacent) {
            set_drag_direction (Direction.START);
        } else {
            set_drag_direction (Direction.NONE);
        }
        return Gdk.DragAction.MOVE;
    }
}
