// private class IconPaddingLayout : Gtk.LayoutManager {
//
//     protected override void measure (Gtk.Widget widget, Gtk.Orientation orientation,
//                                      int for_size, out int minimum, out int natural,
//                                      out int minimum_baseline, out int natural_baseline) {
//         Gtk.Widget child;
//         int minimum_size = 0;
//         int natural_size = 0;
//
//         for (child = widget.get_first_child ();
//              child != null;
//              child = child.get_next_sibling ()) {
//
//             if (!child.should_layout ()) {
//                 continue;
//             }
//
//             int child_min = 0;
//             int child_nat = 0;
//             child.measure (orientation, -1, out child_min, out child_nat, null, null);
//
//             minimum_size = int.max (minimum_size, child_min);
//             natural_size = int.max (natural_size, child_nat);
//         }
//
//         minimum = (int) (n_children * minimum_size / Math.PI + minimum_size);
//         natural = (int) (n_children * natural_size / Math.PI + natural_size);
//         minimum_baseline = -1;
//         natural_baseline = -1;
//     }
//
//     protected override void allocate (Gtk.Widget widget, int width, int height, int baseline) {
//     }
//
//     protected override Gtk.SizeRequestMode get_request_mode (Gtk.Widget widget) {
//         return Gtk.SizeRequestMode.CONSTANT_SIZE;
//     }
// }

public class IconPadding : Gtk.Widget {
    const int TRANSITION_DURATION = 500;
    direction drag_direction = direction.NONE;

    unowned Window window;
    Icon icon;

    private double animation_progress = 1.0;
    private double animation_progress_inv {
        get {
            return (1 - animation_progress);
        }
    }
    private Adw.TimedAnimation ? animation;

    private double padding_offset = 0.0;

    public IconPadding (Window window) {
        this.window = window;
        this.icon = new Icon (window);

        Adw.CallbackAnimationTarget target = new Adw.CallbackAnimationTarget (animation_value_cb);
        animation = new Adw.TimedAnimation (this, 1.0, 0.0, TRANSITION_DURATION, target);

        icon.set_parent (this);

        // set_layout_manager (new Gtk.CustomLayout (layout_get_request_mode,
        //                                           layout_measure,
        //                                           layout_allocate));
        // set_layout_manager_type (typeof(Gtk.BinLayout));
        // size_allocate (icon.get_width (), icon.get_height (), -1);
        // size_allocate (100, 100, -1);
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

        if (!icon.visible){
            return;
        }

        icon.measure (orientation, for_size,
                      out child_min, out child_nat, null, null);

        minimum = child_min;
        natural = child_nat;

        if (orientation != Gtk.Orientation.HORIZONTAL) {
            return;
        }
        print ("MIN: %i %i\n", minimum, natural);

        switch (drag_direction) {
            case direction.LEFT :
                minimum *= 2;
                natural *= 2;
                break;
            case direction.RIGHT:
                minimum *= 2;
                natural *= 2;
                break;
            case direction.NONE:
                break;
        }
    }

    protected override void size_allocate (int width, int height, int baseline) {
        Gtk.Requisition child_req;
        icon.get_preferred_size (out child_req, null);

        Gtk.Allocation allocation = Gtk.Allocation () {
            x = 0,
            y = 0,
            width = child_req.width,
            height = child_req.height,
        };
        switch (drag_direction) {
            case direction.LEFT :
                allocation.x += allocation.width;
                break;
            case direction.RIGHT:
                break;
            case direction.NONE:
                break;
        }

        icon.allocate_size (allocation, -1);
    }

    void animation_value_cb (double progress) {
        animation_progress = progress;

        queue_draw ();
    }

    // public override void measure (Gtk.Orientation orientation, int for_size,
    // out int minimum, out int natural,
    // out int minimum_baseline, out int natural_baseline) {
    // }

    public override void snapshot (Gtk.Snapshot snapshot) {
        // size_allocate (100, 100, -1);
        var clip = Graphene.Rect () {
            origin = Graphene.Point.zero (),
            size = Graphene.Size () {
                width = get_width (),
                height = get_height (),
            },
        };
        // snapshot.push_clip (clip);
        var point = Graphene.Point () {
            x = 0,
            y = 0,
        };
        // snapshot.translate (point);
        snapshot_child (icon, snapshot);

        // snapshot.pop ();
    }

    public inline void init (IconState state) {
        icon.init (state);
        // size_allocate (100, 100, -1);

        init_dnd ();
    }

    public inline void disconnect_from_signals () {
        icon.disconnect_from_signals ();
    }

    private void set_drag_direction (direction dir) {
        drag_direction = dir;

        queue_resize ();

        // Start the animation
        // animation.set_value_to (0);
        // animation.play ();
    }

    private void init_dnd () {
        // Don't support DND for minimized icons
        if (icon.state.minimized) {
            return;
        }

        // Drag Source
        Gtk.DragSource drag_source = new Gtk.DragSource ();
        drag_source.set_actions (Gdk.DragAction.MOVE);
        add_controller (drag_source);
        drag_source.prepare.connect ((x, y) => {
            drag_source.set_icon (new Gtk.WidgetPaintable (icon.image),
                                  (int) x, (int) y);

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

        // Drag Target
        Gtk.DropTarget drop_target = new Gtk.DropTarget (typeof (IconState),
                                                         Gdk.DragAction.MOVE);
        drop_target.set_preload (true);
        add_controller (drop_target);
        drop_target.enter.connect (() => {
            set_drag_direction (direction.NONE);
            return Gdk.DragAction.MOVE;
        });
        drop_target.leave.connect (() => set_drag_direction (direction.NONE));
        drop_target.motion.connect ((x, y) => {
            // Skip self
            Value ? value = drop_target.get_value ();
            if (value == null || !value.holds (typeof (IconState))
                || icon.state == value.get_object ()) {
                return 0;
            }
            IconState drag_state = (IconState) value.get_object ();

            direction adjacent = window.icon_is_adjacent (icon.state, drag_state);
            int half_width = get_width () / 2;

            direction dir = x > half_width ? direction.RIGHT : direction.LEFT;
            // Ignore setting padding offset when it's the neighbouring icon
            bool is_adjacent = adjacent != direction.NONE && dir == adjacent;
            if (dir == direction.RIGHT && !is_adjacent) {
                set_drag_direction (direction.RIGHT);
            } else if (dir == direction.LEFT && !is_adjacent) {
                set_drag_direction (direction.LEFT);
            } else {
                set_drag_direction (direction.NONE);
            }
            return Gdk.DragAction.MOVE;
        });
        drop_target.drop.connect ((value, x, y) => {
            if (!value.holds (typeof (IconState))) {
                warning ("Tried DND for invalid type: %s", value.type_name ());
            }
            unowned IconState drop_state = (IconState) value.get_object ();
            if (drop_state == null || drop_state == icon.state) {
                return false;
            }

            int half_width = get_width () / 2;
            direction dir = x > half_width ? direction.RIGHT : direction.LEFT;
            bool result = false;
            if (drop_state.pinned || icon.state.pinned) {
                result |= pinnedList.dnd_drop (icon.state, drop_state, dir);
            }
            if (!icon.state.pinned) {
                // Reposition icon (includes pinned -> unpinned dnd)
                result |= drop_state.request_icon_reposition (icon.state, dir);
            }
            return result;
        });
    }
}





