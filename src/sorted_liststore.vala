public class SortedListStore : Object {
    public Gtk.SortListModel sorted_list { get; private set; }

    private ListStore list_store;

    public SortedListStore () {
        Gtk.Sorter sorter = new Gtk.CustomSorter (sorter_function);
        Gtk.Sorter section_sorter = new Gtk.CustomSorter (section_function);

        this.list_store = new ListStore (typeof (IconState));
        this.sorted_list = new Gtk.SortListModel (list_store, sorter);

        this.sorted_list.set_section_sorter (section_sorter);

        // Add all pinned
        foreach (string app_id in pinnedList.pinned) {
            IconState state = new IconState (app_id, true);
            state.request_icon_reposition.connect (IconState.request_icon_reposition_callback);
            append (state);
        }

        assert_nonnull (pinnedList);
        pinnedList.pinned_added.connect (pinned_added);
        pinnedList.pinned_removed.connect (pinned_removed);

        foreign_helper.toplevel_changed.connect (toplevel_changed);
        foreign_helper.toplevel_focused.connect (toplevel_focused);
        foreign_helper.toplevel_minimize.connect (toplevel_minimize);
        foreign_helper.toplevel_added.connect (toplevel_added);
        foreign_helper.toplevel_removed.connect (toplevel_removed);
    }

    public void get_section (uint position, out uint out_start, out uint out_end) {
        sorted_list.get_section (position, out out_start, out out_end);
    }

    public inline Object ? get_item (uint position) {
        return list_store.get_item (position);
    }

    public inline Object ? get_item_sorted (uint position) {
        return sorted_list.get_item (position);
    }

    public uint get_n_items () {
        return sorted_list.get_n_items ();
    }

    public void insert (uint position, Object item) {
        list_store.insert (position, item);
    }

    public void append (Object item) {
        list_store.append (item);
    }

    public void remove (uint position) {
        list_store.remove (position);
    }

    private bool _find (ListModel model, Object item, out uint position) {
        for (uint i = 0; i < model.get_n_items (); i++) {
            Object ? object = model.get_item (i);
            if (object == item) {
                position = i;
                return true;
            }
        }

        position = uint.MAX;
        return false;
    }

    /// Uses pointer comparison to find the correct item position
    public bool find_sorted (Object item, out uint position) {
        return _find (sorted_list, item, out position);
    }

    /// Uses pointer comparison to find the correct item position
    public bool find (Object item, out uint position) {
        return _find (list_store, item, out position);
    }

    public void invalidate_sort () {
        sorted_list.sorter.changed (Gtk.SorterChange.DIFFERENT);
        sorted_list.section_sorter.changed (Gtk.SorterChange.DIFFERENT);
    }

    public void debug_print_list_store () {
        print ("List Store:\n");
        for (uint i = 0; i < get_n_items (); i++) {
            IconState ? state = (IconState ?) sorted_list.get_item (i);
            char prefix = '-';
            if (state.pinned) {
                prefix = 'P';
            }
            if (state.minimized) {
                prefix = 'M';
            }
            print ("\t%u: %c %s\n", i, prefix, state?.app_id);
        }
        print ("\n");
    }

    //
    // Dock Implemenation
    //

    private void pinned_added (string app_id) {
        for (uint i = 0; i < get_n_items (); i++) {
            IconState ? state = (IconState ?) get_item_sorted (i);
            if (state != null && state.app_id == app_id && !state.minimized) {
                state.pinned = true;
                invalidate_sort ();
                return;
            }
        }

        // Fallback for if a repositioned pinned toplevel isn't running (not in list)
        IconState state = new IconState (app_id, true);
        state.request_icon_reposition.connect (IconState.request_icon_reposition_callback);
        append (state);
    }

    private void pinned_removed (string app_id) {
        for (uint i = 0; i < get_n_items (); i++) {
            IconState ? state = (IconState ?) get_item (i);
            if (state != null && state.app_id == app_id && state.pinned) {
                state.pinned = false;
                // No running toplevels
                if (state.get_first_toplevel () == null) {
                    remove (i);
                } else {
                    invalidate_sort ();
                }
                break;
            }
        }
    }

    private void toplevel_changed (Toplevel toplevel) {
        // TODO: Remove from icon group if app_id changed
    }

    private void toplevel_focused (Toplevel toplevel) {
        unowned IconState ? state = toplevel.icon_state;
        if (state == null) {
            for (uint i = 0; i < get_n_items (); i++) {
                IconState iter_state = (IconState) get_item (i);
                if (!iter_state.minimized && iter_state.app_id == toplevel.app_id) {
                    state = iter_state;
                    break;
                }
            }
        }
        return_if_fail (state != null);

        state.focused = toplevel.activated;

        if (!toplevel.done) {
            return;
        }

        state.move_to_front (toplevel);
        state.refresh ();
    }

    private void toplevel_minimize (Toplevel toplevel) {
        if (toplevel == null || !toplevel.done) {
            return;
        }

        if (toplevel.minimized) {
            IconState state = new IconState (toplevel.app_id, false);
            state.minimized = true;
            state.add_toplevel (toplevel);
            append (state);
        } else {
            for (uint i = 0; i < get_n_items (); i++) {
                IconState state = (IconState) get_item (i);
                unowned Toplevel first_toplevel = state.get_first_toplevel ();
                if (first_toplevel == null) {
                    continue;
                }
                if (state.minimized && first_toplevel == toplevel) {
                    uint pos;
                    if (find (state, out pos)) {
                        remove (pos);
                    } else {
                        error ("Could not find ID in ListStore");
                    }
                    return;
                }
            }
        }
    }

    private void toplevel_added (Toplevel toplevel) {
        if (toplevel.minimized) {
            toplevel_minimize (toplevel);
        }

        // Check if icon with app_id already exists
        for (uint i = 0; i < get_n_items (); i++) {
            IconState state = (IconState) get_item (i);
            if (!state.minimized && state.app_id == toplevel.app_id) {
                toplevel.icon_state = state;
                state.add_toplevel (toplevel);
                return;
            }
        }

        // No previous icon with app_id exists, create a new one
        IconState state = new IconState (toplevel.app_id, false);
        toplevel.icon_state = state;
        state.add_toplevel (toplevel);
        state.request_icon_reposition.connect (IconState.request_icon_reposition_callback);
        append (state);
    }

    private void toplevel_removed (Toplevel toplevel) {
        // Remove all minimized icons with Toplevel
        for (uint i = 0; i < get_n_items (); i++) {
            IconState state = (IconState) get_item (i);
            unowned Toplevel first_toplevel = state.get_first_toplevel ();
            if (first_toplevel == null) {
                continue;
            }
            if (state.minimized && first_toplevel == toplevel) {
                uint pos;
                if (find (state, out pos)) {
                    remove (pos);
                } else {
                    error ("Could not find ID in ListStore");
                }
                // NOTE: Don't break here, we want to remove all minimized Icons of Toplevel
            }
        }

        unowned IconState ? state = toplevel.icon_state;
        if (state == null) {
            for (uint i = 0; i < get_n_items (); i++) {
                IconState iter_state = (IconState) get_item (i);
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
                if (find (state, out pos)) {
                    remove (pos);
                } else {
                    error ("Could not find ID in ListStore");
                }
            }
        }
    }

    private int sorter_function (Object ? a, Object ? b) {
        unowned IconState id_a = (IconState) a;
        unowned IconState id_b = (IconState) b;

        if (id_a.pinned && id_b.pinned) {
            int a_pos = list_index (pinnedList.pinned, id_a.app_id, strcmp);
            int b_pos = list_index (pinnedList.pinned, id_b.app_id, strcmp);
            return a_pos < b_pos ? -1 : 1;
        }
        return section_function (a, b);
    }

    private int section_function (Object ? a, Object ? b) {
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
}
