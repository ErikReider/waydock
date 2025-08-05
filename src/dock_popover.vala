class DockPopover : Gtk.Popover {
    unowned Icon icon;

    private const int per_line = 3;

    public DockPopover (Icon icon) {
        this.icon = icon;

        set_autohide (true);
        set_cascade_popdown (true);

        Gtk.FlowBox popover_box = new Gtk.FlowBox ();
        popover_box.set_max_children_per_line (3);
        uint length = icon.state.toplevels.length ();
        if (length < per_line) {
            popover_box.set_max_children_per_line (length);
        }
        popover_box.set_homogeneous (true);
        popover_box.set_row_spacing (12);
        popover_box.set_column_spacing (12);
        popover_box.set_selection_mode (Gtk.SelectionMode.NONE);
        popover_box.child_activated.connect ((child) => {
            unowned Toplevel toplevel = child.get_data<unowned Toplevel> ("toplevel");
            WlrForeignHelper.activate_toplevel (toplevel);
            popdown ();
        });
        set_child (popover_box);

        foreach (unowned Toplevel toplevel in icon.state.toplevels) {
            var child = new Gtk.FlowBoxChild ();
            child.add_css_class ("popover-item");
            child.set_data<unowned Toplevel> ("toplevel", toplevel);
            popover_box.append (child);

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            child.set_child (box);

            var image = new Gtk.Image ();
            image.add_css_class ("popover-image");
            set_image_icon_from_app_info (icon.app_info, toplevel.app_id, image);
            box.append (image);

            var label = new Gtk.Label (toplevel.title);
            label.add_css_class ("popover-label");
            label.set_max_width_chars (25);
            label.set_ellipsize (Pango.EllipsizeMode.END);
            label.set_halign (Gtk.Align.CENTER);
            label.set_lines (3);
            box.append (label);
        }
    }
}
