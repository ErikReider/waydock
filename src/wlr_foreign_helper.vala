using WLR.ForeignToplevel;

public class Toplevel {
    public uint64 id = 0;

    public string title;
    public string app_id;
    public Handle parent;

    public bool fullscreen = false;
    public bool activated = false;
    public bool minimized = false;
    public bool maximized = false;

    public void * data;

    public unowned Handle handle;

    public bool done = false;
}

public class WlrForeignHelper : Object {
    private static Wl.RegistryListener registry_listener = Wl.RegistryListener () {
        global = registry_handle_global,
    };
    private const HandleListener toplevel_listener = {
        handle_title,
        handle_app_id,
        handle_output_enter,
        handle_output_leave,
        handle_state,
        handle_done,
        handle_closed,
        handle_parent,
    };
    private const ManagerListener manager_listener = {
        handle_toplevel,
        handle_finished,
    };

    private Manager ? manager;
    private uint64 id_counter = 0;

    public static List<Toplevel *> toplevels = new List<Toplevel *> ();
    public bool started = false;

    public signal void toplevel_changed (Toplevel * toplevel);
    public signal void toplevel_focused (Toplevel * toplevel);
    public signal void toplevel_added (Toplevel * toplevel);
    public signal void toplevel_removed (owned Toplevel toplevel);

    public void start () {
        if (started) {
            return;
        }
        started = true;
        unowned Wl.Display wl_display = get_wl_display ();
        var wl_registry = wl_display.get_registry ();
        wl_registry.add_listener (registry_listener, this);

        if (wl_display.roundtrip () < 0) {
            return;
        }
    }

    public void add_toplevel (Toplevel * toplevel) {
        toplevel->id = id_counter;
        toplevels.append (toplevel);
        id_counter++;
        foreign_helper.toplevel_added (toplevel);
    }

    public static bool activate_toplevel (Toplevel * toplevel) {
        if (toplevel == null) {
            return false;
        }

        unowned Gdk.Seat seat = Gdk.Display.get_default ().get_default_seat ();
        assert (seat is Gdk.Wayland.Seat);
        toplevel->handle.activate (((Gdk.Wayland.Seat) seat).get_wl_seat ());

        return true;
    }

    private void registry_handle_global (Wl.Registry wl_registry, uint32 name,
                                         string @interface, uint32 version) {
        if (@interface == "zwlr_foreign_toplevel_manager_v1") {
            manager = wl_registry.bind<Manager> (name, ref Manager.iface, version);
            if (manager == null) {
                GLib.error ("Manager is null!");
            }

            unowned Wl.Display wl_display = get_wl_display ();
            manager.add_listener (manager_listener, this);
            if (wl_display.roundtrip () < 0) {
                return;
            }
        }
    }

    //
    // Manager
    //

    private void handle_toplevel (Manager manager, Handle handle) {
        unowned Wl.Display wl_display = get_wl_display ();

        Toplevel * toplevel = new Toplevel ();
        toplevel->handle = handle;
        handle.add_listener (toplevel_listener, toplevel);
        if (wl_display.roundtrip () < 0) {
            return;
        }
    }

    private void handle_finished (Manager manager) {
        // TODO: Finished
        print ("FINISHED\n");
    }

    //
    // Toplevel
    //

    private static void handle_title (void * data, Handle handle,
                                      string title) {
        Toplevel * toplevel = (Toplevel *) data;
        toplevel->title = title;
    }

    private static void handle_app_id (void * data, Handle handle,
                                       string app_id) {
        Toplevel * toplevel = (Toplevel *) data;
        toplevel->app_id = app_id;
    }

    private static void handle_output_enter (void * data, Handle handle,
                                             Wl.Output output) {
        Toplevel * toplevel = (Toplevel *) data;
    }

    private static void handle_output_leave (void * data, Handle handle,
                                             Wl.Output output) {
        Toplevel * toplevel = (Toplevel *) data;
    }

    private static void handle_state (void * data, Handle handle,
                                      Wl.Array states) {
        Toplevel * toplevel = (Toplevel *) data;

        bool initial_activated_state = toplevel->activated;

        toplevel->maximized = false;
        toplevel->minimized = false;
        toplevel->activated = false;
        toplevel->fullscreen = false;

        // Iterate through wl_array (extended the wl_array_for_each macro)
        uint32 * pos;
        for (pos = states.data;
             states.size != 0 &&
             (char *) pos < ((char *) states.data + states.size);
             pos++) {
            switch (*pos) {
                case state.MAXIMIZED :
                    toplevel->maximized = true;
                    break;
                case state.MINIMIZED:
                    toplevel->minimized = true;
                    break;
                case state.ACTIVATED:
                    toplevel->activated = true;
                    break;
                case state.FULLSCREEN:
                    toplevel->fullscreen = true;
                    break;
            }
        }
        if (initial_activated_state != toplevel->activated) {
            foreign_helper.toplevel_focused (toplevel);
        }
    }

    private static void handle_done (void * data, Handle handle) {
        Toplevel * toplevel = (Toplevel *) data;
        if (!toplevel->done) {
            toplevel->done = true;
            foreign_helper.add_toplevel (toplevel);
        } else {
            foreign_helper.toplevel_changed (toplevel);
        }
    }

    private static void handle_closed (void * data, Handle handle) {
        Toplevel * toplevel = (Toplevel *) data;
        toplevels.remove (toplevel);
        // TODO: Does vala auto copy the toplevel?
        foreign_helper.toplevel_removed (toplevel);
        free (toplevel);
    }

    private static void handle_parent (void * data, Handle handle,
                                       Handle ? parent) {
        Toplevel * toplevel = (Toplevel *) data;
        // TODO: Parent
    }

    // TODO: handle.set_rectangle for minimization animation target (dock surface, dock surface relative position)
}
