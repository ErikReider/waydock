public class SortedListStore : Object {
    public ListStore list_store { get; private set; }
    public Gtk.SortListModel sorted_list { get; private set; }

    public SortedListStore (Type item_type,
                            Gtk.Sorter sorter,
                            Gtk.Sorter section_sorter) {
        list_store = new ListStore (typeof (IconState));
        sorted_list = new Gtk.SortListModel (list_store, sorter);

        sorted_list.set_section_sorter (section_sorter);
    }

    public void get_section (uint position, out uint out_start, out uint out_end) {
        sorted_list.get_section (position, out out_start, out out_end);
    }

    public GLib.Object ? get_item (uint position) {
        return list_store.get_item (position);
    }

    public GLib.Object ? get_item_sorted (uint position) {
        return sorted_list.get_item (position);
    }

    public uint get_n_items () {
        return list_store.get_n_items ();
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

    public void debug_print_list_store () {
        print ("List Store:\n");
        for (uint i = 0; i < get_n_items (); i++) {
            IconState ? state = (IconState ?) sorted_list.get_item (i);
            print ("\t%u: %s\n", i, state?.app_id);
        }
        print ("\n");
    }
}
