public class IconPadding : Gtk.Widget {
    const int TRANSITION_DURATION = 250;
    direction drag_direction = direction.NONE;

    unowned Window window;
    Icon icon;

    private double start_animation_progress = 0.0;
    private Adw.TimedAnimation ? start_animation;
    private double end_animation_progress = 0.0;
    private Adw.TimedAnimation ? end_animation;

    public IconPadding (Window window) {
        this.window = window;
        this.icon = new Icon (window);

        Adw.CallbackAnimationTarget start_target = new Adw.CallbackAnimationTarget (start_animation_value_cb);
        start_animation = new Adw.TimedAnimation (this, 0.0, 0.0, TRANSITION_DURATION, start_target);
        Adw.CallbackAnimationTarget end_target = new Adw.CallbackAnimationTarget (end_animation_value_cb);
        end_animation = new Adw.TimedAnimation (this, 0.0, 0.0, TRANSITION_DURATION, end_target);

        icon.set_parent (this);
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

        // TODO: Change depending on dock direction
        if (orientation != Gtk.Orientation.HORIZONTAL) {
            return;
        }

        minimum += (int) (minimum * start_animation_progress + minimum * end_animation_progress);
        natural += (int) (natural * start_animation_progress + natural * end_animation_progress);
    }

    protected override void size_allocate (int width, int height, int baseline) {
        Gtk.Requisition child_req;
        icon.get_preferred_size (out child_req, null);

        Gsk.Transform transform = new Gsk.Transform ()
            .translate (
                Graphene.Point ().init (
                    // TODO: Dock direction
                    (int) (child_req.width * start_animation_progress),
                    0)
            );
        icon.allocate (child_req.width, child_req.height, -1, transform);
    }

    void start_animation_value_cb (double progress) {
        start_animation_progress = progress;
        queue_resize ();
    }

    void end_animation_value_cb (double progress) {
        end_animation_progress = progress;
        queue_resize ();
    }

    public inline void init (IconState state) {
        icon.init (state);
        init_dnd ();
    }

    public inline void disconnect_from_signals () {
        icon.disconnect_from_signals ();
    }

    private void set_drag_direction (direction dir) {
        if (drag_direction == dir) {
            return;
        }
        drag_direction = dir;

        switch (dir) {
            case direction.START:
                start_animation.value_to = 1.0;
                end_animation.value_to = 0.0;
                break;
            case direction.END:
                start_animation.value_to = 0.0;
                end_animation.value_to = 1.0;
                break;
            case direction.NONE:
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

            direction dir = x > half_width ? direction.END : direction.START;
            // Ignore setting padding offset when it's the neighbouring icon
            bool is_adjacent = adjacent != direction.NONE && dir == adjacent;
            if (dir == direction.END && !is_adjacent) {
                set_drag_direction (direction.END);
            } else if (dir == direction.START && !is_adjacent) {
                set_drag_direction (direction.START);
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
            direction dir = x > half_width ? direction.END : direction.START;
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
