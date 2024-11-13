public class Window : Gtk.ApplicationWindow {
    private const int margin = 6;
    private const int dock_min_size = margin * 2;

    private Gtk.Box box;
    private Gtk.Box pinned_box;
    private Gtk.Box running_box;

    private List<unowned Icon> toplevel_icons = new List<unowned Icon> ();

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

        box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
        box.set_halign (Gtk.Align.CENTER);
        box.set_hexpand (false);
        set_css_name ("dock");
        add_css_class ("dock");
        this.set_child (box);

        pinned_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        box.append (pinned_box);

        running_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        box.append (running_box);

        foreach (string app_id in pinned) {
            Icon icon = new Icon (app_id);
            icon.pinned = true;
            toplevel_icons.append (icon);
            pinned_box.append (icon);
        }

        foreign_helper.toplevel_changed.connect (toplevel_changed);
        foreign_helper.toplevel_focused.connect (toplevel_focused);
        foreign_helper.toplevel_added.connect (toplevel_added);
        foreign_helper.toplevel_removed.connect (toplevel_removed);

        height_request = dock_min_size;
        width_request = dock_min_size;
    }

    private void toplevel_changed (Toplevel * toplevel) {
        // TODO: Remove from icon group if app_id changed
    }

    private void toplevel_focused (Toplevel * toplevel) {
        if (!toplevel->done) {
            return;
        }

        Icon icon = null;
        if (toplevel->data != null) {
            icon = (Icon) toplevel->data;
        } else {
            foreach (unowned Icon iter_icon in toplevel_icons) {
                if (iter_icon.app_id == toplevel->app_id) {
                    icon = iter_icon;
                    break;
                }
            }
        }

        icon.toplevels.remove (toplevel);
        icon.toplevels.insert (toplevel, 0);
    }

    private void toplevel_added (Toplevel * toplevel) {
        // Check if icon with app_id already exists
        foreach (unowned Icon icon in toplevel_icons) {
            if (icon.app_id == toplevel->app_id) {
                toplevel->data = icon;
                icon.add_toplevel (toplevel);
                return;
            }
        }

        // No previous icon with app_id exists, create a new one
        Icon icon = new Icon (toplevel->app_id);
        toplevel_icons.append (icon);
        running_box.append (icon);

        icon.add_toplevel (toplevel);
        toplevel->data = icon;
    }

    private void toplevel_removed (owned Toplevel toplevel) {
        unowned Icon icon = null;
        if (toplevel.data != null) {
            icon = (Icon) toplevel.data;
        } else {
            foreach (unowned Icon iter_icon in toplevel_icons) {
                if (iter_icon.app_id == toplevel.app_id) {
                    icon = iter_icon;
                    break;
                }
            }
        }

        if (icon == null) {
            return;
        }

        if (icon.remove_toplevel (toplevel)) {
            if (!icon.pinned) {
                running_box.remove (icon);
                toplevel_icons.remove (icon);
            }
        }
    }
}
