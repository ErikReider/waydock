public class Window : Gtk.ApplicationWindow, Gtk.Orientable {
    private DockList list;

    public unowned Gdk.Monitor monitor { get; construct set; }

    public Direction orientation_direction { get; set; default = Direction.START; }
    public Gtk.Orientation orientation { get; set; default = Gtk.Orientation.VERTICAL; }
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

        self_settings.changed.connect (settings_changed);

        list = new DockList (this);
        set_child (list);

        set_position ();
        set_anchor ();
    }

    private void settings_changed (string name) {
        switch (name) {
            case "position":
                set_position ();
                set_anchor ();
                break;
            case "pinned":
                // TODO:
                break;
            default:
                break;
        }
    }

    private void set_position () {
        switch ((Position) self_settings.get_enum ("position")) {
            case Position.TOP:
                orientation = Gtk.Orientation.HORIZONTAL;
                orientation_direction = Direction.START;
                break;
            case Position.LEFT:
                orientation = Gtk.Orientation.VERTICAL;
                orientation_direction = Direction.START;
                break;
            case Position.RIGHT:
                orientation = Gtk.Orientation.VERTICAL;
                orientation_direction = Direction.END;
                break;
            case Position.BOTTOM:
                orientation = Gtk.Orientation.HORIZONTAL;
                orientation_direction = Direction.END;
                break;
        }
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
                    case Direction.START:
                        list.add_css_class ("start");
                        GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, true);
                        GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, false);
                        GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, true);
                        GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, true);
                        break;
                    case Direction.END:
                    case Direction.NONE:
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
                    case Direction.START:
                    case Direction.NONE:
                        list.add_css_class ("start");
                        GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, true);
                        GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, true);
                        GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, true);
                        GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, false);
                        break;
                    case Direction.END:
                        list.add_css_class ("end");
                        GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, true);
                        GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, true);
                        GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, false);
                        GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, true);
                        break;
                }
                break;
        }

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

            unowned Gdk.Surface ?surface = get_surface ();
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

    public void debug_print_list_store () {
        icons_list.debug_print_list_store ();
    }
}
