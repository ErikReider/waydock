public class IconTooltip : Gtk.Popover {
    private Gtk.Label label;

    public IconTooltip () {
        Object (
            accessible_role: Gtk.AccessibleRole.TOOLTIP,
            can_target: false,
            can_focus: false,
            has_tooltip: false,
            autohide: false,
            has_arrow: false
        );

        add_css_class ("tooltip");

        label = new Gtk.Label (null) {
            ellipsize = Pango.EllipsizeMode.END,
            wrap = true,
            wrap_mode = Pango.WrapMode.WORD,
            natural_wrap_mode = Gtk.NaturalWrapMode.WORD,
            lines = 2,
            max_width_chars = 32,
            justify = Gtk.Justification.CENTER,
        };
        set_child (label);
    }

    public void set_text (string ?text) {
        if (text == null || text.length == 0) {
            label.set_text ("");
        }
        label.set_text (text);
    }
}
