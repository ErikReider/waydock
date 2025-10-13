public class IconState : Object {
    public string ?app_id;
    public bool pinned;
    public bool minimized = false;
    public bool focused { get; set; default = false; }

    public List<unowned Toplevel> toplevels;

    public unowned LauncherEntry ?launcher_entry { get; private set; default = null; }

    public DesktopAppInfo ?app_info { get; private set; default = null; }
    public KeyFile ?keyfile { get; private set; default = null; }

    public signal void refresh ();
    public signal void toplevel_added (Toplevel toplevel);

    public IconState (string ?app_id, bool pinned) {
        this.app_id = app_id;
        this.pinned = pinned;
        this.toplevels = new List<unowned Toplevel> ();

        try_set_app_info ();

        unity_service.entry_added.connect (unity_entry_added);
    }

    private void try_set_app_info () {
        string[] titles = {};
        foreach (unowned Toplevel toplevel in toplevels) {
            titles += toplevel.title;
        }

        // TODO: Check if other icon has same app_info
        // (ex: gtk4-demo and gtk4-demo fishbowl demo share the same desktop file)
        app_info = get_app_info (app_id, titles);
        if (app_info != null) {
            keyfile = new KeyFile ();
            try {
                keyfile.load_from_file (app_info.get_filename (), KeyFileFlags.NONE);
            } catch (Error e) {
                warning ("Could not load KeyFile for: %s", app_id);
                keyfile = null;
            }
        }
    }

    public void move_to_front (Toplevel toplevel) {
        toplevels.remove (toplevel);
        toplevels.insert (toplevel, 0);
    }

    public void add_toplevel (Toplevel toplevel) {
        toplevels.append (toplevel);
        if (app_info == null) {
            try_set_app_info ();
        }
        toplevel_added (toplevel);
    }

    /// Returns true if there are no toplevels left
    public bool remove_toplevel (owned Toplevel toplevel) {
        toplevels.remove (toplevel);
        refresh ();
        return toplevels.is_empty ();
    }

    public unowned Toplevel ?get_first_toplevel () {
        unowned List<unowned Toplevel> first_link = toplevels.first ();
        if (first_link == null) {
            return null;
        }
        return first_link.data;
    }

    public bool request_icon_reposition (IconState target_state, Direction dir) {
        if (dir == Direction.NONE) {
            return false;
        }
        if (pinned || minimized || target_state.pinned || target_state.minimized) {
            debug ("Skipping pinned/minimized reordering");
            return false;
        }

        // Firstly, remove drag from list so that the target_position doesn't
        // get messed up
        uint drag_position;
        if (!icons_list.find (this, out drag_position)) {
            debug ("Could not find drag_state in List Store");
            return false;
        }
        icons_list.remove (drag_position);

        // Find the target position and adjust the index depending on if
        // dropped behind or in front of the target icon
        uint insert_index;
        if (!icons_list.find (target_state, out insert_index)) {
            debug ("Could not find target_state in List Store");
            return false;
        }
        if (dir == Direction.END) {
            insert_index = (insert_index + 1).clamp (0, icons_list.get_n_items ());
        }

        icons_list.insert (insert_index, this);
        return true;
    }

    private void unity_entry_added (string app_id, LauncherEntry entry) {
        if (app_info ? .get_id () != app_id) {
            return;
        }

        if (this.launcher_entry != null) {
            this.launcher_entry.changed.disconnect (unity_entry_changed);
        }

        this.launcher_entry = entry;
        this.launcher_entry.changed.connect (unity_entry_changed);

        refresh ();
    }

    private void unity_entry_changed () {
        refresh ();
    }
}
