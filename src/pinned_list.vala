class PinnedList {
    public List<string> pinned;

    public signal void pinned_removed (string app_id);
    public signal void pinned_added (string app_id);
    public signal void pinned_moved (string app_id);

    public PinnedList () {
        pinned = new List<string>();

        if (!self_settings.settings_schema.has_key ("pinned")) {
            return;
        }
        var v_type = self_settings.settings_schema.get_key ("pinned").get_value_type ();
        if (!v_type.is_array ()) {
            stderr.printf (
                "Set GSettings error:" +
                " Set value type \"array\" not equal to gsettings type \"%s\"\n",
                v_type);
            return;
        }

        string[] array = self_settings.get_value ("pinned").get_strv ();
        foreach (string app_id in array) {
            pinned.append (app_id);
        }
    }

    private void set_pinned () {
        if (!self_settings.settings_schema.has_key ("pinned")) {
            warning ("Could not set pinned");
            return;
        }

        string[] pinned_array = {};
        foreach (var app_id in pinned) {
            pinned_array += app_id;
        }

        bool result = self_settings.set_strv ("pinned", pinned_array);
        if (!result) {
            warning ("Could not set pinned: %u", pinned.length ());
            return;
        }
    }

    public void remove_pinned (string app_id) {
        unowned List<string> node = pinned.find_custom (app_id, strcmp);
        if (node != null) {
            pinned.remove_link (node);
            set_pinned ();
            pinned_removed (app_id);
        }
    }

    public void add_pinned (string app_id) {
        unowned List<string> node = pinned.find_custom (app_id, strcmp);
        if (node == null) {
            pinned.append (app_id);
            set_pinned ();
            pinned_added (app_id);
        }
    }

    public bool dnd_drop (IconState target_state,
                          IconState drop_state,
                          Direction dir) {
        if (dir == Direction.NONE) {
            return false;
        }

        unowned List<string> node = pinned.find_custom (target_state.app_id, strcmp);
        if (node == null) {
            // Try to unpin the dropped item if it's pinned
            remove_pinned (drop_state.app_id);
            return false;
        }

        // Only get the next node on right due to always calling `insert_before`.
        // Not needed for the left direction
        bool insert_last = false;
        if (dir == Direction.END) {
            if (node == pinned.last ()) {
                insert_last = true;
            } else {
                node = node.next;
            }
        }

        // Don't replace self
        if (node.data == drop_state.app_id) {
            return false;
        }

        // Remove if already pinned
        unowned List<string> drop_node = pinned.find_custom (drop_state.app_id, strcmp);
        if (drop_node != null) {
            pinned.remove_link (drop_node);
            pinned_removed (drop_state.app_id);
        }

        // Insert at the new position
        if (insert_last) {
            pinned.append (drop_state.app_id);
        } else {
            pinned.insert_before (node, drop_state.app_id);
        }

        // Refresh the gschema and call the signal
        set_pinned ();
        pinned_added (drop_state.app_id);

        return true;
    }
}

