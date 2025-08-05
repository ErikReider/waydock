public class IconState : Object {
    public string ? app_id;
    public bool pinned;
    public bool minimized = false;

    public List<unowned Toplevel> toplevels;

    public signal void refresh ();
    public signal void toplevel_added (Toplevel toplevel);
    public signal bool request_icon_reposition (IconState target_state, direction dir);

    public IconState (string ? app_id, bool pinned) {
        this.app_id = app_id;
        this.pinned = pinned;
        this.toplevels = new List<unowned Toplevel> ();
    }

    public void move_to_front (Toplevel toplevel) {
        toplevels.remove (toplevel);
        toplevels.insert (toplevel, 0);
    }

    public void add_toplevel (Toplevel toplevel) {
        toplevels.append (toplevel);
        toplevel_added (toplevel);
    }

    /// Returns true if there are no toplevels left
    public bool remove_toplevel (owned Toplevel toplevel) {
        toplevels.remove (toplevel);
        refresh ();
        return toplevels.is_empty ();
    }

    public unowned Toplevel ? get_first_toplevel () {
        unowned List<unowned Toplevel> first_link = toplevels.first ();
        if (first_link == null) {
            return null;
        }
        return first_link.data;
    }

    public static bool request_icon_reposition_callback (IconState drag_state,
                                                         IconState target_state,
                                                         direction dir) {
        if (dir == direction.NONE) {
            return false;
        }
        if (drag_state.pinned || drag_state.minimized
            || target_state.pinned || target_state.minimized) {
            debug ("Skipping pinned/minimized reordering");
            return false;
        }

        // Firstly, remove drag from list so that the target_position doesn't
        // get messed up
        uint drag_position;
        if (!list_object.find (drag_state, out drag_position)) {
            debug ("Could not find drag_state in List Store");
            return false;
        }
        list_object.remove (drag_position);

        // Find the target position and adjust the index depending on if
        // dropped behind or in front of the target icon
        uint insert_index;
        if (!list_object.find (target_state, out insert_index)) {
            debug ("Could not find target_state in List Store");
            return false;
        }
        if (dir == direction.END) {
            insert_index = (insert_index + 1).clamp (0, list_object.get_n_items ());
        }

        list_object.insert (insert_index, drag_state);
        return true;
    }

}

