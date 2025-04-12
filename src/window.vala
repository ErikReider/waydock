public class Window : Gtk.ApplicationWindow {
    private const int margin = 6;
    private const int dock_min_size = margin * 2;

    private SortedListStore list_object;

    private Gtk.ListView list;

    public Window (Gtk.Application app) {
        Object (application: app);

        // Layer shell
        GtkLayerShell.init_for_window (this);
        GtkLayerShell.set_layer (this, GtkLayerShell.Layer.TOP);
        GtkLayerShell.set_namespace (this, "waydock");
        GtkLayerShell.set_exclusive_zone (this, 0);
        GtkLayerShell.auto_exclusive_zone_enable (this);

        GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, false);
        GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, true);
        GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, false);
        GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, false);

        GtkLayerShell.set_margin (this, GtkLayerShell.Edge.TOP, 0);
        GtkLayerShell.set_margin (this, GtkLayerShell.Edge.BOTTOM, margin);
        GtkLayerShell.set_margin (this, GtkLayerShell.Edge.LEFT, margin);
        GtkLayerShell.set_margin (this, GtkLayerShell.Edge.RIGHT, margin);

        set_halign (Gtk.Align.CENTER);
        set_resizable (false); // Fixes centered position not resetting

        set_css_name ("dock");
        add_css_class ("dock");

        Gtk.Sorter sorter = new Gtk.CustomSorter (sorter_function);
        Gtk.Sorter section_sorter = new Gtk.CustomSorter (section_function);
        list_object = new SortedListStore (typeof (IconState), sorter, section_sorter);

        var factory = new Gtk.SignalListItemFactory ();
        factory.setup.connect ((factory, object) => {
            Gtk.ListItem item = (Gtk.ListItem) object;
            item.set_child (new IconPadding (this));
        });
        factory.bind.connect ((factory, object) => {
            Gtk.ListItem item = (Gtk.ListItem) object;
            unowned IconPadding icon = (IconPadding) item.get_child ();
            unowned IconState id = (IconState) item.get_item ();
            icon.init (id);
        });
        factory.unbind.connect ((factory, object) => {
            Gtk.ListItem item = (Gtk.ListItem) object;
            unowned IconPadding icon = (IconPadding) item.get_child ();
            icon.disconnect_from_signals ();
        });

        var header_factory = new Gtk.SignalListItemFactory ();
        header_factory.setup.connect ((factory, object) => {
            Gtk.ListHeader item = (Gtk.ListHeader) object;
            item.set_child (new Gtk.Separator (Gtk.Orientation.VERTICAL));
        });
        header_factory.bind.connect ((factory, object) => {
            Gtk.ListHeader item = (Gtk.ListHeader) object;
            if (item.start == 0) {
                item.get_child ().set_visible (false);
            }
        });
        header_factory.unbind.connect ((factory, object) => {
            Gtk.ListHeader item = (Gtk.ListHeader) object;
            item.get_child ().set_visible (true);
        });

        Gtk.NoSelection no_selection = new Gtk.NoSelection (list_object.sorted_list);
        list = new Gtk.ListView (no_selection, factory);
        list.set_orientation (Gtk.Orientation.HORIZONTAL);
        list.set_header_factory (header_factory);
        set_child (list);

        // Add all pinned
        foreach (string app_id in pinnedList.pinned) {
            IconState state = new IconState (app_id, true);
            state.request_icon_reposition.connect (request_icon_reposition_callback);
            list_object.append (state);
        }

        pinnedList.pinned_added.connect (pinned_added);
        pinnedList.pinned_removed.connect (pinned_removed);

        foreign_helper.toplevel_changed.connect (toplevel_changed);
        foreign_helper.toplevel_focused.connect (toplevel_focused);
        foreign_helper.toplevel_minimize.connect (toplevel_minimize);
        foreign_helper.toplevel_added.connect (toplevel_added);
        foreign_helper.toplevel_removed.connect (toplevel_removed);

        height_request = dock_min_size;
        width_request = dock_min_size;
    }

    private void pinned_added (string app_id) {
        for (uint i = 0; i < list_object.get_n_items (); i++) {
            IconState ? state = (IconState ?) list_object.get_item (i);
            if (state != null && state.app_id == app_id && !state.minimized) {
                state.pinned = true;
                list_object.list_store.items_changed (i, 1, 1);
                return;
            }
        }

        // Fallback for if a repositioned pinned toplevel isn't running (not in list)
        IconState state = new IconState (app_id, true);
        state.request_icon_reposition.connect (request_icon_reposition_callback);
        list_object.append (state);
    }

    private void pinned_removed (string app_id) {
        for (uint i = 0; i < list_object.get_n_items (); i++) {
            IconState ? state = (IconState ?) list_object.get_item (i);
            if (state != null && state.app_id == app_id && state.pinned) {
                state.pinned = false;
                // No running toplevels
                if (state.get_first_toplevel () == null) {
                    list_object.remove (i);
                } else {
                    list_object.list_store.items_changed (i, 1, 1);
                }
                break;
            }
        }
    }

    private bool request_icon_reposition_callback (IconState drag_state,
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
        if (dir == direction.RIGHT) {
            insert_index = (insert_index + 1).clamp (0, list_object.get_n_items ());
        }

        list_object.insert (insert_index, drag_state);
        return true;
    }

    private void toplevel_changed (Toplevel * toplevel) {
        // TODO: Remove from icon group if app_id changed
    }

    private void toplevel_focused (Toplevel * toplevel) {
        if (!toplevel->done) {
            return;
        }

        IconState ? state = null;
        if (toplevel->data != null) {
            state = (IconState) toplevel->data;
        } else {
            for (uint i = 0; i < list_object.get_n_items (); i++) {
                IconState iter_state = (IconState) list_object.get_item (i);
                if (!iter_state.minimized && iter_state.app_id == toplevel->app_id) {
                    state = iter_state;
                    break;
                }
            }
        }

        state.move_to_front (toplevel);
        state.refresh ();
    }

    private void toplevel_minimize (Toplevel * toplevel) {
        if (toplevel == null || !toplevel->done) {
            return;
        }

        if (toplevel->minimized) {
            IconState state = new IconState (toplevel->app_id, false);
            state.minimized = true;
            state.add_toplevel (toplevel);
            list_object.append (state);
        } else {
            for (uint i = 0; i < list_object.get_n_items (); i++) {
                IconState state = (IconState) list_object.get_item (i);
                Toplevel * first_toplevel = state.get_first_toplevel ();
                if (first_toplevel == null) {
                    continue;
                }
                if (state.minimized && first_toplevel == toplevel) {
                    uint pos;
                    if (list_object.find (state, out pos)) {
                        list_object.remove (pos);
                    } else {
                        error ("Could not find ID in ListStore");
                    }
                    return;
                }
            }
        }
    }

    private void toplevel_added (Toplevel * toplevel) {
        if (toplevel->minimized) {
            toplevel_minimize (toplevel);
        }

        // Check if icon with app_id already exists
        for (uint i = 0; i < list_object.get_n_items (); i++) {
            IconState state = (IconState) list_object.get_item (i);
            if (!state.minimized && state.app_id == toplevel->app_id) {
                toplevel->data = state;
                state.add_toplevel (toplevel);
                return;
            }
        }

        // No previous icon with app_id exists, create a new one
        IconState state = new IconState (toplevel->app_id, false);
        toplevel->data = state;
        state.add_toplevel (toplevel);
        state.request_icon_reposition.connect (request_icon_reposition_callback);
        list_object.append (state);
    }

    private void toplevel_removed (owned Toplevel toplevel) {
        // Remove all minimized icons with Toplevel
        for (uint i = 0; i < list_object.get_n_items (); i++) {
            IconState state = (IconState) list_object.get_item (i);
            Toplevel * first_toplevel = state.get_first_toplevel ();
            if (first_toplevel == null) {
                continue;
            }
            if (state.minimized && first_toplevel == toplevel) {
                uint pos;
                if (list_object.find (state, out pos)) {
                    list_object.remove (pos);
                } else {
                    error ("Could not find ID in ListStore");
                }
                // NOTE: Don't break here, we want to remove all minimized Icons of Toplevel
            }
        }

        unowned IconState state = (IconState) toplevel.data;
        if (state == null) {
            for (uint i = 0; i < list_object.get_n_items (); i++) {
                IconState iter_state = (IconState) list_object.get_item (i);
                if (!iter_state.minimized && iter_state.app_id == toplevel.app_id) {
                    state = iter_state;
                    break;
                }
            }
        }

        // Could not find, must already be destroyed
        if (state == null) {
            return;
        }

        if (state.remove_toplevel (toplevel)) {
            if (!state.pinned) {
                uint pos;
                if (list_object.find (state, out pos)) {
                    list_object.remove (pos);
                } else {
                    error ("Could not find ID in ListStore");
                }
            }
        }
    }

    private int sorter_function (void * a, void * b) {
        unowned IconState id_a = (IconState) a;
        unowned IconState id_b = (IconState) b;

        if (id_a.pinned && id_b.pinned) {
            int a_pos = list_index (pinnedList.pinned, id_a.app_id, strcmp);
            int b_pos = list_index (pinnedList.pinned, id_b.app_id, strcmp);
            return a_pos < b_pos ? -1 : 1;
        }
        return section_function (a, b);
    }

    private int section_function (void * a, void * b) {
        unowned IconState id_a = (IconState) a;
        unowned IconState id_b = (IconState) b;

        // Minimized Toplevels go last
        if (id_a.minimized && !id_b.minimized) {
            return 1;
        } else if (!id_a.minimized && id_b.minimized) {
            return -1;
        }

        if (id_a.pinned && !id_b.pinned) {
            return -1;
        } else if (!id_a.pinned && id_b.pinned) {
            return 1;
        }
        return 0;
    }

    public direction icon_is_adjacent (IconState reference, IconState sibling) {
        if (reference == null || sibling == null || reference == sibling
            || reference.pinned != sibling.pinned) {
            return direction.NONE;
        }

        uint ref_pos;
        if (!list_object.find_sorted (reference, out ref_pos)) {
            debug ("Could not find reference icon state in List Store");
            return direction.NONE;
        }

        if (ref_pos - 1 >= 0) {
            IconState ? state = (IconState ?) list_object.get_item_sorted (ref_pos - 1);
            if (state != null && state == sibling) {
                return direction.LEFT;
            }
        }
        if (ref_pos + 1 < list_object.get_n_items ()) {
            IconState ? state = (IconState ?) list_object.get_item_sorted (ref_pos + 1);
            if (state != null && state == sibling) {
                return direction.RIGHT;
            }
        }

        return direction.NONE;
    }

    public void debug_print_list_store () {
        list_object.debug_print_list_store ();
    }
}
