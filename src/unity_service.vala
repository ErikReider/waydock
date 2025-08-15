public class LauncherEntry : Object {
    public string app_uri { get; set construct; }

    public int64 count { get; set; default = 0; }
    public bool count_visible { get; set; default = false; }
    public double progress { get; set; default = 0.0; }
    public bool progress_visible { get; set; default = false; }
    public bool urgent { get; set; default = false; }

    public LauncherEntry (string app_uri) {
        this.app_uri = app_uri;
    }

    public signal void changed ();
}

/** Documentation: https://wiki.ubuntu.com/Unity/LauncherAPI */
public class UnityService : Object {
    DBusConnection connection;

    // app_id.desktop : LauncherEntry
    HashTable<string, LauncherEntry> entries;

    construct {
        try {
            connection = Bus.get_sync (BusType.SESSION, null);
        } catch (Error e) {
            error ("Could not get Session Bus!");
        }
        Bus.own_name (BusType.SESSION, "com.canonical.Unity",
                      BusNameOwnerFlags.ALLOW_REPLACEMENT,
                      () => {},
                      () => {},
                      () => {
            stderr.printf ("Could not acquire Unity Launcher API name!...\n");
        });

        entries = new HashTable<string, LauncherEntry> (str_hash, str_equal);
    }

    public void start () {
        connection.signal_subscribe (null, "com.canonical.Unity.LauncherEntry", null, null, null,
            DBusSignalFlags.NONE, handle_entry_update);
    }

    public signal void entry_added (string app_id, LauncherEntry entry);

    private void handle_entry_update (DBusConnection connection, string ? sender_name,
                                      string object_path, string interface_name,
                                      string signal_name, Variant parameters) {
        if (parameters == null || signal_name == null || sender_name == null) {
            return;
        }

        if (signal_name == "Update") {
            handle_update (sender_name, parameters);
        }
    }

    private void handle_update (string sender_name, Variant parameters) {
        if (parameters.get_type_string () != "(sa{sv})") {
            critical ("Skipping Launcher parameters of type \"%s\" from sender %s",
                parameters.get_type_string (), sender_name);
            return;
        }

        string app_uri;
        VariantIter props_iter;
        parameters.get ("(sa{sv})", out app_uri, out props_iter);

        string app_id = app_uri.replace ("application://", "");

        bool new_entry = false;
        LauncherEntry entry;
        if (!entries.lookup_extended (app_id, null, out entry)) {
            new_entry = true;
            entry = new LauncherEntry (app_uri);
            entries.set (app_id, entry);
        }

        string prop_key;
        Variant prop_value;
        while (props_iter.next ("{sv}", out prop_key, out prop_value)) {
            switch (prop_key) {
                case "count":
                    entry.count = prop_value.get_int64 ();
                    break;
                case "count-visible":
                    entry.count_visible = prop_value.get_boolean ();
                    break;
                case "progress":
                    entry.progress = prop_value.get_double ();
                    break;
                case "progress-visible":
                    entry.progress_visible = prop_value.get_boolean ();
                    break;
                case "urgent":
                    entry.urgent = prop_value.get_boolean ();
                    break;
            }
        }

        if (new_entry) {
            entry_added (app_id, entry);
        } else {
            entry.changed ();
        }
    }
}
