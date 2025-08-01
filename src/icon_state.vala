public class IconState : Object {
    public string ? app_id;
    public bool pinned;
    public bool minimized = false;

    public List<unowned Toplevel> toplevels;

    public unowned Window window { get; construct set; }

    public signal void refresh ();
    public signal void toplevel_added (Toplevel toplevel);
    public signal bool request_icon_reposition (IconState target_state, direction dir);

    public IconState (Window window, string ? app_id, bool pinned) {
        Object(window: window);
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
}

