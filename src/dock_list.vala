public enum AlignMode {
    START,
    CENTER,
    END;

    public string class_name () {
        switch (this) {
            case AlignMode.START:
                return "align-start";
            default:
            case AlignMode.CENTER:
                return "align-center";
            case AlignMode.END:
                return "align-end";
        }
    }

    public Gtk.Align to_align () {
        switch (this) {
            case AlignMode.START:
                return Gtk.Align.START;
            default:
            case AlignMode.CENTER:
                return Gtk.Align.CENTER;
            case AlignMode.END:
                return Gtk.Align.END;
        }
    }
}

private struct WidgetMeasurements {
    int min;
    int nat;
}

private struct WidgetAlloc {
    float offset;
    int size;
}

public class DockList : Gtk.Widget, Gtk.Orientable {
    public Gtk.Orientation orientation { get; set; default = Gtk.Orientation.HORIZONTAL; }

    private List<unowned DockItem> items = new List<unowned DockItem> ();
    private List<unowned Gtk.Separator> separators = new List<unowned Gtk.Separator> ();
    private int num_children = 0;

    bool fill_space = false;
    AlignMode align_mode = AlignMode.CENTER;

    private unowned Window window;

    public DockList (Window window) {
        Object (
            css_name: "docklist",
            accessible_role: Gtk.AccessibleRole.LIST,
            overflow: Gtk.Overflow.HIDDEN
        );

        add_css_class ("dock");

        this.window = window;

        for (uint i = 0; i < icons_list.get_n_items (); i++) {
            items_changed (i, 0, 1);
        }
        icons_list.sorted_list.items_changed.connect (items_changed);
        icons_list.sorted_list.section_sorter.changed.connect (sections_changed);
    }

    private void items_changed (uint position, uint removed, uint added) {
        if (removed > 0) {
            unowned List<unowned DockItem> link = items.nth (position);
            int i = 0;
            do {
                if (link.data != null) {
                    link.data.unparent ();
                }

                unowned List<unowned DockItem> next = link.next;
                items.remove_link (link);

                link = next;
                num_children--;
                i++;
            } while (link != null && i < removed);
        }

        for (uint i = 0; i < added; i++) {
            DockItem item = new DockItem (window);
            item.init (icons_list.get_item_sorted (position + i));

            item.insert_before (this, items.nth_data (position + i));
            items.insert (item, (int) (position + i));
            num_children++;
        }

        sections_changed ();

        queue_resize ();
    }

    private void sections_changed () {
        // Remove all of the previous separators
        while (!separators.is_empty ()) {
            unowned List<unowned Gtk.Separator> link = separators.nth (0);
            link.data.unparent ();
            separators.delete_link (link);
            num_children--;
        }
        warn_if_fail (separators.is_empty ());

        for (uint end = 0; ; ) {
            uint start;
            icons_list.get_section (end, out start, out end);

            uint n_items = icons_list.get_n_items ();
            if (start >= n_items || end > n_items) {
                break;
            }

            if (end - start == 0) {
                break;
            }

            if (start == 0) {
                continue;
            }

            Gtk.Separator separator = new Gtk.Separator (window.opposite_orientation);
            unowned DockItem item = items.nth_data (start);
            separator.insert_before (this, item);
            separators.append (separator);
            num_children++;
        }
    }

    public void refresh_items () {
        foreach (unowned DockItem item in items) {
            item.refresh ();
        }

        sections_changed ();
    }

    public void set_align_mode (bool force) {
        bool fill_space_value = self_settings.get_boolean ("fill-space");
        AlignMode align_mode_value = (AlignMode) self_settings.get_enum ("align-mode");
        if (fill_space == fill_space_value
            && align_mode == align_mode_value
            && !force) {
            return;
        }
        fill_space = fill_space_value;
        align_mode = align_mode_value;

        remove_css_class ("fill-space");
        remove_css_class ("align-start");
        remove_css_class ("align-center");
        remove_css_class ("align-end");
        if (fill_space) {
            add_css_class ("fill-space");
            add_css_class (align_mode.class_name ());

            switch (orientation) {
                case Gtk.Orientation.HORIZONTAL:
                    set_halign (Gtk.Align.FILL);
                    set_valign (Gtk.Align.CENTER);
                    break;
                case Gtk.Orientation.VERTICAL:
                    set_halign (Gtk.Align.CENTER);
                    set_valign (Gtk.Align.FILL);
                    break;
            }
        } else {
            switch (orientation) {
                case Gtk.Orientation.HORIZONTAL:
                    set_halign (align_mode.to_align ());
                    set_valign (Gtk.Align.CENTER);
                    break;
                case Gtk.Orientation.VERTICAL:
                    set_halign (Gtk.Align.CENTER);
                    set_valign (align_mode.to_align ());
                    break;
            }
        }

        queue_allocate ();
    }

    public override void dispose () {
        for (unowned Gtk.Widget ?child = get_first_child ();
             child != null;
             child = get_first_child ()) {
            child.unparent ();
        }

        while (!items.is_empty ()) {
            items.delete_link (items.first ());
        }
        warn_if_fail (items.is_empty ());

        base.dispose ();
    }

    protected override Gtk.SizeRequestMode get_request_mode () {
        for (unowned Gtk.Widget ?child = get_first_child ();
             child != null;
             child = child.get_next_sibling ()) {
            if (child.get_request_mode () != Gtk.SizeRequestMode.CONSTANT_SIZE) {
                return Gtk.SizeRequestMode.HEIGHT_FOR_WIDTH;
            }
        }
        return Gtk.SizeRequestMode.CONSTANT_SIZE;
    }

    protected override void compute_expand_internal (out bool hexpand_p,
                                                     out bool vexpand_p) {
        hexpand_p = false;
        vexpand_p = false;

        for (unowned Gtk.Widget ?child = get_first_child ();
             child != null;
             child = child.get_next_sibling ()) {
            hexpand_p |= child.compute_expand (Gtk.Orientation.HORIZONTAL);
            vexpand_p |= child.compute_expand (Gtk.Orientation.VERTICAL);
        }
    }

    private inline T orientated_size<T> (T horizontal, T vertical) {
        switch (window.orientation) {
            default :
            case Gtk.Orientation.HORIZONTAL :
                return horizontal;
            case Gtk.Orientation.VERTICAL :
                return vertical;
        }
    }

    private void compute_size (int width,
                               int height,
                               out int total_size,
                               out WidgetAlloc[] child_sizes) {
        total_size = 0;
        child_sizes = new WidgetAlloc[num_children];

        int num_vexpand_children = 0;
        WidgetMeasurements measured_height = WidgetMeasurements ();
        WidgetMeasurements[] heights = new WidgetMeasurements[num_children];
        int total_min = 0;
        int total_nat = 0;

        int i = 0;
        for (unowned Gtk.Widget ?child = get_first_child ();
             child != null;
             child = child.get_next_sibling ()) {
            if (!child.should_layout ()) {
                continue;
            }

            int min, nat;
            child.measure (window.orientation, orientated_size (height, width),
                           out min, out nat, null, null);
            heights[i] = WidgetMeasurements () {
                min = min,
                nat = nat,
            };
            total_min += min;
            total_nat += nat;

            if (child.compute_expand (window.orientation)) {
                num_vexpand_children++;
            }

            i++;
        }

        bool allocate_nat = false;
        int extra_size = 0;
        if (window.orientation == Gtk.Orientation.VERTICAL
            && height >= measured_height.nat) {
            allocate_nat = true;
            extra_size = height - measured_height.nat;
        } else if (window.orientation == Gtk.Orientation.HORIZONTAL
                   && width >= measured_height.nat) {
            allocate_nat = true;
            extra_size = width - measured_height.nat;
        } else {
            warn_if_reached ();
        }

        int offset = 0;
        i = 0;
        for (unowned Gtk.Widget ?child = get_first_child ();
             child != null;
             child = child.get_next_sibling ()) {
            WidgetMeasurements computed_measurement = heights[i];
            WidgetAlloc child_allocation = WidgetAlloc () {
                offset = 0,
                size = computed_measurement.min,
            };
            if (allocate_nat) {
                child_allocation.size = computed_measurement.nat;
            }

            if (child.compute_expand (window.orientation)) {
                child_allocation.size += extra_size / num_vexpand_children;
            }

            child_allocation.offset = offset;
            child_sizes[i] = child_allocation;

            total_size += child_allocation.size;
            offset += child_allocation.size;
            i++;
        }
    }

    protected override void size_allocate (int width, int height, int baseline) {
        int size_unit = orientated_size (width, height);

        // Save the already computed widget heights. We need the total height
        // for calculating the reversed list animation, so two loops through the
        // widgets is necessary...
        int total_size;
        WidgetAlloc[] sizes;
        compute_size (width, height, out total_size, out sizes);
        // Limit the totoal size to the window size
        total_size = int.min (size_unit, total_size);

        float align_shift = 0;
        if (fill_space) {
            switch (align_mode) {
                case AlignMode.START :
                    break;
                case AlignMode.CENTER :
                    align_shift = (size_unit - total_size) / 2;
                    break;
                case AlignMode.END:
                    align_shift = size_unit - total_size;
                    break;
            }
            align_shift = float.max (align_shift, 0);
        }

        // Allocate the size and position of each item
        uint index = 0;
        for (unowned Gtk.Widget ?child = get_first_child ();
             child != null;
             child = child.get_next_sibling ()) {
            if (!child.should_layout ()) {
                index++;
                continue;
            }

            WidgetAlloc child_allocation = sizes[index];
            float offset = child_allocation.offset + align_shift;
            child.allocate (
                orientated_size (child_allocation.size, width),
                orientated_size (height, child_allocation.size),
                baseline,
                new Gsk.Transform ().translate (
                    Graphene.Point ().init (
                        orientated_size<float ?> (offset, 0.0f) ?? 0.0f,
                        orientated_size<float ?> (0.0f, offset) ?? 0.0f
                    )
                )
            );
            index++;
        }
    }

    protected override void measure (Gtk.Orientation orientation, int for_size,
                                     out int minimum, out int natural,
                                     out int minimum_baseline, out int natural_baseline) {
        minimum = 0;
        natural = 0;
        minimum_baseline = -1;
        natural_baseline = -1;

        int min = 0, nat = 0;
        int largest_min = 0, largest_nat = 0;
        for (unowned Gtk.Widget ?child = get_first_child ();
             child != null;
             child = child.get_next_sibling ()) {
            if (!child.should_layout ()) {
                continue;
            }

            int child_min, child_nat;
            child.measure (orientation, for_size,
                           out child_min, out child_nat, null, null);
            min += child_min;
            nat += child_nat;
            largest_min = int.max (largest_min, child_min);
            largest_nat = int.max (largest_min, child_nat);
        }

        if (orientation == window.orientation) {
            // TODO: Limit to monitor size
            int w_height = int.MAX;
            minimum = int.min (min, w_height);
            natural = int.min (nat, w_height);
        } else {
            minimum = largest_min;
            natural = largest_nat;
        }
    }
}
