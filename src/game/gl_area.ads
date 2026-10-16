--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Thin binding to GtkGLArea, which GtkAda 21 does not wrap.

with Glib;
with Gtk.Widget;
with Interfaces.C;
with System;

package GL_Area is

   type Gtk_GL_Area_Record is new Gtk.Widget.Gtk_Widget_Record with null record;
   type Gtk_GL_Area is access all Gtk_GL_Area_Record'Class;

   procedure Gtk_New (Area : out Gtk_GL_Area);

   procedure Set_Required_Version (Area : access Gtk_GL_Area_Record'Class;
                                   Major, Minor : Integer);
   procedure Set_Has_Depth_Buffer (Area : access Gtk_GL_Area_Record'Class;
                                   Value : Boolean);
   procedure Make_Current (Area : access Gtk_GL_Area_Record'Class);
   procedure Queue_Render (Area : access Gtk_GL_Area_Record'Class);
   function Error_Message (Area : access Gtk_GL_Area_Record'Class) return String;
   --  "" if the area has no error

   --  C-level signal callbacks (the GtkAda marshallers know nothing about
   --  GtkGLArea's signals, so we connect directly).
   type Render_Callback is access function
     (Area, Context, Data : System.Address) return Glib.Gboolean
     with Convention => C;
   type Void_Callback is access procedure (Widget, Data : System.Address)
     with Convention => C;

   procedure On_Render (Area : access Gtk_GL_Area_Record'Class;
                        Cb : Render_Callback);
   procedure On_Realize (Area : access Gtk_GL_Area_Record'Class;
                         Cb : Void_Callback);
   procedure On_Unrealize (Area : access Gtk_GL_Area_Record'Class;
                           Cb : Void_Callback);

   subtype C_Int is Interfaces.C.int;

end GL_Area;
