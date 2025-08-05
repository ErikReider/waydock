public class Window : Gtk.ApplicationWindow, Gtk.Orientable {
    private DockList list;

    public unowned Gdk.Monitor monitor { get; construct set; }

    public direction orientation_direction { get; set; default = direction.END; }
    public Gtk.Orientation orientation { get; set; default = Gtk.Orientation.HORIZONTAL; }
    public Gtk.Orientation opposite_orientation {
        get {
            switch (orientation) {
            case Gtk.Orientation.VERTICAL:
                return Gtk.Orientation.HORIZONTAL;
            default:
            case Gtk.Orientation.HORIZONTAL:
                return Gtk.Orientation.VERTICAL;
            }
        }
    }

    private Graphene.Rect dock_bounds = Graphene.Rect.zero ();

    // TODO: Parse ~/.config/monitors.xml for primary output
    public Window (Gtk.Application app, Gdk.Monitor monitor) {
        Object (
            application: app,
            monitor: monitor
        );

        // Layer shell
        GtkLayerShell.init_for_window (this);
        GtkLayerShell.set_layer (this, GtkLayerShell.Layer.TOP);
        GtkLayerShell.set_namespace (this, "waydock");
        GtkLayerShell.set_exclusive_zone (this, 0);
        GtkLayerShell.auto_exclusive_zone_enable (this);
        GtkLayerShell.set_monitor (this, monitor);

        set_halign (Gtk.Align.FILL);
        set_valign (Gtk.Align.FILL);

        var factory = new Gtk.SignalListItemFactory ();
        factory.setup.connect ((factory, object) => {
            Gtk.ListItem item = (Gtk.ListItem) object;
            item.set_child (new DockItem (this));
        });
        factory.bind.connect ((factory, object) => {
            Gtk.ListItem item = (Gtk.ListItem) object;
            unowned DockItem icon = (DockItem) item.get_child ();
            unowned IconState id = (IconState) item.get_item ();
            icon.init (id);
        });
        factory.unbind.connect ((factory, object) => {
            Gtk.ListItem item = (Gtk.ListItem) object;
            unowned DockItem icon = (DockItem) item.get_child ();
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

        list = new DockList (this);
        set_child (list);

        set_anchor ();
    }

    private void set_anchor () {
        list.set_orientation (orientation);
        list.set_halign (Gtk.Align.CENTER);
        list.set_valign (Gtk.Align.CENTER);

        list.remove_css_class ("vertical");
        list.remove_css_class ("horizontal");
        list.remove_css_class ("start");
        list.remove_css_class ("end");

        switch (orientation) {
        case Gtk.Orientation.HORIZONTAL:
            list.add_css_class ("horizontal");
            switch (orientation_direction) {
            case direction.START:
                list.add_css_class ("start");
                GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, true);
                GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, false);
                GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, true);
                GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, true);
                break;
            case direction.END:
            case direction.NONE:
                list.add_css_class ("end");
                GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, false);
                GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, true);
                GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, true);
                GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, true);
                break;
            }
            break;
        case Gtk.Orientation.VERTICAL:
            list.add_css_class ("vertical");
            switch (orientation_direction) {
            case direction.START:
            case direction.NONE:
                list.add_css_class ("start");
                GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, true);
                GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, true);
                GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, true);
                GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, false);
                break;
            case direction.END:
                list.add_css_class ("end");
                GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, true);
                GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, true);
                GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, false);
                GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, true);
                break;
            }
            break;
        }

        // TODO: Update icon dot positions
        // TODO: Resize all the icons to fit the width/height (shrink)
        list.refresh_items ();
    }

    public override void size_allocate (int width, int height, int baseline) {
        base.size_allocate (width, height, baseline);

        // Set the input region to only be the size of the actual dock
        Graphene.Rect bounds;
        if (list.compute_bounds (this, out bounds)
            && !bounds.equal (this.dock_bounds)) {
            this.dock_bounds = bounds;

            unowned Gdk.Surface ? surface = get_surface ();
            if (surface == null) {
                return;
            }

            Cairo.RectangleInt rect = Cairo.RectangleInt () {
                x = (int) dock_bounds.get_x (),
                y = (int) dock_bounds.get_y (),
                width = (int) dock_bounds.get_width (),
                height = (int) dock_bounds.get_height (),
            };
            Cairo.Region region = new Cairo.Region.rectangle (rect);
            surface.set_input_region (region);
        }
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
                return direction.START;
            }
        }
        if (ref_pos + 1 < list_object.get_n_items ()) {
            IconState ? state = (IconState ?) list_object.get_item_sorted (ref_pos + 1);
            if (state != null && state == sibling) {
                return direction.END;
            }
        }

        return direction.NONE;
    }

    public void debug_print_list_store () {
        list_object.debug_print_list_store ();
    }
}
