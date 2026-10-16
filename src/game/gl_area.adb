with Interfaces.C.Strings;

package body GL_Area is

   use Interfaces.C;

   function gtk_gl_area_new return System.Address
     with Import, Convention => C, External_Name => "gtk_gl_area_new";
   procedure gtk_gl_area_set_required_version (A : System.Address; Major, Minor : int)
     with Import, Convention => C,
          External_Name => "gtk_gl_area_set_required_version";
   procedure gtk_gl_area_set_has_depth_buffer (A : System.Address; V : Glib.Gboolean)
     with Import, Convention => C,
          External_Name => "gtk_gl_area_set_has_depth_buffer";
   procedure gtk_gl_area_make_current (A : System.Address)
     with Import, Convention => C, External_Name => "gtk_gl_area_make_current";
   procedure gtk_gl_area_queue_render (A : System.Address)
     with Import, Convention => C, External_Name => "gtk_gl_area_queue_render";
   function gtk_gl_area_get_error (A : System.Address) return System.Address
     with Import, Convention => C, External_Name => "gtk_gl_area_get_error";

   function g_signal_connect_data
     (Instance : System.Address; Signal : Strings.chars_ptr;
      Handler : System.Address; Data : System.Address;
      Destroy : System.Address; Flags : int) return unsigned_long
     with Import, Convention => C, External_Name => "g_signal_connect_data";

   type GError_Rec is record
      Domain  : Interfaces.Unsigned_32;
      Code    : int;
      Message : Strings.chars_ptr;
   end record
     with Convention => C;

   procedure Gtk_New (Area : out Gtk_GL_Area) is
   begin
      Area := new Gtk_GL_Area_Record;
      Area.Set_Object (gtk_gl_area_new);
   end Gtk_New;

   procedure Set_Required_Version (Area : access Gtk_GL_Area_Record'Class;
                                   Major, Minor : Integer) is
   begin
      gtk_gl_area_set_required_version (Area.Get_Object, int (Major), int (Minor));
   end Set_Required_Version;

   procedure Set_Has_Depth_Buffer (Area : access Gtk_GL_Area_Record'Class;
                                   Value : Boolean) is
   begin
      gtk_gl_area_set_has_depth_buffer (Area.Get_Object, (if Value then 1 else 0));
   end Set_Has_Depth_Buffer;

   procedure Make_Current (Area : access Gtk_GL_Area_Record'Class) is
   begin
      gtk_gl_area_make_current (Area.Get_Object);
   end Make_Current;

   procedure Queue_Render (Area : access Gtk_GL_Area_Record'Class) is
   begin
      gtk_gl_area_queue_render (Area.Get_Object);
   end Queue_Render;

   function Error_Message (Area : access Gtk_GL_Area_Record'Class) return String
   is
      use type System.Address;
      E : constant System.Address := gtk_gl_area_get_error (Area.Get_Object);
   begin
      if E = System.Null_Address then
         return "";
      end if;
      declare
         Err : GError_Rec with Import, Address => E;
      begin
         return Strings.Value (Err.Message);
      end;
   end Error_Message;

   procedure Connect (Area : access Gtk_GL_Area_Record'Class; Signal : String;
                      Handler : System.Address)
   is
      Name : Strings.chars_ptr := Strings.New_String (Signal);
      Id   : unsigned_long;
   begin
      Id := g_signal_connect_data (Area.Get_Object, Name, Handler,
                                   System.Null_Address, System.Null_Address, 0);
      pragma Unreferenced (Id);
      Strings.Free (Name);
   end Connect;

   procedure On_Render (Area : access Gtk_GL_Area_Record'Class;
                        Cb : Render_Callback) is
   begin
      Connect (Area, "render", Cb.all'Address);
   end On_Render;

   procedure On_Realize (Area : access Gtk_GL_Area_Record'Class;
                         Cb : Void_Callback) is
   begin
      Connect (Area, "realize", Cb.all'Address);
   end On_Realize;

   procedure On_Unrealize (Area : access Gtk_GL_Area_Record'Class;
                           Cb : Void_Callback) is
   begin
      Connect (Area, "unrealize", Cb.all'Address);
   end On_Unrealize;

end GL_Area;
