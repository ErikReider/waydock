// vim: ft=vala

namespace WLR.ForeignToplevel {

    //
    // Manager
    //

    [CCode (cheader_filename = "wlr-foreign-toplevel-management-client-protocol.h", cname = "struct zwlr_foreign_toplevel_manager_v1", cprefix = "zwlr_foreign_toplevel_manager_v1_")]
    public class Manager : Wl.Proxy {
        [CCode (cheader_filename = "wlr-foreign-toplevel-management-client-protocol.h", cname = "zwlr_foreign_toplevel_manager_v1_interface")]
        public static Wl.Interface iface;
        public void set_user_data (void * user_data);
        public void * get_user_data ();
        public uint32 get_version ();
        public void destroy ();

        public void stop ();
        public int add_listener (ManagerListener listener, void * data);
    }

    [CCode (cname = "struct zwlr_foreign_toplevel_manager_v1_listener", has_type_id = false)]
    public struct ManagerListener {
        public ManagerListenerToplevel toplevel;
        public ManagerListenerFinished finished;
    }

    [CCode (has_target = false, has_typedef = false)]
    public delegate void ManagerListenerToplevel (void * data, Manager manager, Handle toplevel);

    [CCode (has_target = false, has_typedef = false)]
    public delegate void ManagerListenerFinished (void * data, Manager manager);

    //
    // Handle
    //

    [CCode (cheader_filename = "wlr-foreign-toplevel-management-client-protocol.h", cname = "enum zwlr_foreign_toplevel_handle_v1_state", cprefix = "ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_", has_type_id = false)]
    public enum state {
        MAXIMIZED = 0,
        MINIMIZED = 1,
        ACTIVATED = 2,
        FULLSCREEN = 3,
    }

    [CCode (cheader_filename = "wlr-foreign-toplevel-management-client-protocol.h", cname = "enum zwlr_foreign_toplevel_handle_v1_error", cprefix = "ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_ERROR_", has_type_id = false)]
    public enum error {
        INVALID_RECTANGLE = 0,
    }

    [CCode (cheader_filename = "wlr-foreign-toplevel-management-client-protocol.h", cname = "struct zwlr_foreign_toplevel_handle_v1", cprefix = "zwlr_foreign_toplevel_handle_v1_")]
    public class Handle : Wl.Proxy {
        [CCode (cheader_filename = "wlr-foreign-toplevel-management-client-protocol.h", cname = "zwlr_foreign_toplevel_handle_v1_interface")]
        public static Wl.Interface iface;
        public void set_user_data (void * user_data);
        public void * get_user_data ();
        public uint32 get_version ();
        public void destroy ();

        public int add_listener (HandleListener listener, void * data);

        public void set_maximized ();
        public void unset_maximized ();
        public void set_minimized ();
        public void unset_minimized ();
        public void activate (Wl.Seat seat);
        public void close ();
        public void set_rectangle (Wl.Surface surface, int x, int y, int width, int height);
        public void set_fullscreen ();
        public void unset_fullscreen ();
    }

    [CCode (cname = "struct zwlr_foreign_toplevel_handle_v1_listener", has_type_id = false)]
    public struct HandleListener {
        public ToplevelListenerTitle title;
        public ToplevelListenerAppId app_id;
        public ToplevelListenerOutputEnter output_enter;
        public ToplevelListenerOutputLeave output_leave;
        public ToplevelListenerState state;
        public ToplevelListenerDone done;
        public ToplevelListenerClosed closed;
        public ToplevelListenerParent parent;
    }

    [CCode (has_target = false, has_typedef = false)]
    public delegate void ToplevelListenerTitle (void * data, Handle handle, string title);

    [CCode (has_target = false, has_typedef = false)]
    public delegate void ToplevelListenerAppId (void * data, Handle handle, string app_id);

    [CCode (has_target = false, has_typedef = false)]
    public delegate void ToplevelListenerOutputEnter (void * data, Handle handle, Wl.Output output);

    [CCode (has_target = false, has_typedef = false)]
    public delegate void ToplevelListenerOutputLeave (void * data, Handle handle, Wl.Output output);

    [CCode (has_target = false, has_typedef = false)]
    public delegate void ToplevelListenerState (void * data, Handle handle, Wl.Array state);

    [CCode (has_target = false, has_typedef = false)]
    public delegate void ToplevelListenerDone (void * data, Handle handle);

    [CCode (has_target = false, has_typedef = false)]
    public delegate void ToplevelListenerClosed (void * data, Handle handle);

    [CCode (has_target = false, has_typedef = false)]
    public delegate void ToplevelListenerParent (void * data, Handle handle, Handle ? parent);
}

