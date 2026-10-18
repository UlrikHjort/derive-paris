--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--

with Ada.Numerics;
with Ada.Strings.Fixed;

with Cairo;
with Cairo.Image_Surface;
with Cairo.Png;
with Glib;
with Gtkada.Types;
with Gtk.Drawing_Area;

package body Limit_Sign is

   use Glib;

   Size : constant := 84;

   Area : Gtk.Drawing_Area.Gtk_Drawing_Area;
   Shown_Limit : Natural := 0;
   Shown_Lit   : Boolean := True;

   procedure Paint (Cr : Cairo.Cairo_Context) is
      use Cairo;
      C  : constant Gdouble := Gdouble (Size) / 2.0;
      Pi : constant := Ada.Numerics.Pi;
      Text : constant String :=
        Ada.Strings.Fixed.Trim (Natural'Image (Shown_Limit), Ada.Strings.Left);
      Ext  : aliased Cairo_Text_Extents;
      Str  : Gtkada.Types.Chars_Ptr := Gtkada.Types.New_String (Text);
   begin
      if Shown_Limit = 0 then
         Gtkada.Types.Free (Str);
         return;
      end if;
      --  white disc, red ring (brighter and thicker while flashing)
      Arc (Cr, C, C, C - 2.0, 0.0, 2.0 * Pi);
      Set_Source_Rgb (Cr, 0.97, 0.97, 0.95);
      Fill_Preserve (Cr);
      if Shown_Lit then
         Set_Source_Rgb (Cr, 0.82, 0.08, 0.08);
      else
         Set_Source_Rgb (Cr, 1.0, 0.85, 0.1);
      end if;
      Set_Line_Width (Cr, 9.0);
      Stroke (Cr);
      Arc (Cr, C, C, C - 7.0, 0.0, 2.0 * Pi);
      Set_Source_Rgb (Cr, 0.82, 0.08, 0.08);
      Set_Line_Width (Cr, 4.0);
      Stroke (Cr);
      --  the number
      Select_Font_Face (Cr, "Sans", Cairo_Font_Slant_Normal, Cairo_Font_Weight_Bold);
      Set_Font_Size (Cr, (if Text'Length > 2 then 26.0 else 32.0));
      Text_Extents (Cr, Str, Ext'Access);
      Gtkada.Types.Free (Str);
      Set_Source_Rgb (Cr, 0.05, 0.05, 0.05);
      Move_To (Cr, C - Ext.Width / 2.0 - Ext.X_Bearing, C - Ext.Height / 2.0 - Ext.Y_Bearing);
      Show_Text (Cr, Text);
   end Paint;

   function Draw
     (Self : access Gtk.Widget.Gtk_Widget_Record'Class;
      Cr   : Cairo.Cairo_Context) return Boolean
   is
      pragma Unreferenced (Self);
   begin
      Paint (Cr);
      return True;
   end Draw;

   function Create return Gtk.Widget.Gtk_Widget is
   begin
      Gtk.Drawing_Area.Gtk_New (Area);
      Area.Set_Size_Request (Size, Size);
      Area.On_Draw (Draw'Access);
      return Gtk.Widget.Gtk_Widget (Area);
   end Create;

   procedure Set (Limit : Natural; Over : Boolean; Time : Float) is
      --  while too fast: twice a second the ring flashes yellow
      Lit : constant Boolean := not Over or else Time - Float'Floor (Time) < 0.5;
   begin
      if Limit /= Shown_Limit or else Lit /= Shown_Lit then
         Shown_Limit := Limit;
         Shown_Lit := Lit;
         if Gtk.Drawing_Area."/=" (Area, null) then
            Area.Queue_Draw;
         end if;
      end if;
   end Set;

   procedure Save_Png (File_Name : String) is
      use Cairo;
      Surface : constant Cairo_Surface :=
        Cairo.Image_Surface.Create (Cairo.Image_Surface.Cairo_Format_ARGB32, Size, Size);
      Cr      : constant Cairo_Context := Create (Surface);
      Status  : Cairo_Status;
   begin
      Paint (Cr);
      Status := Cairo.Png.Write_To_Png (Surface, File_Name);
      pragma Unreferenced (Status);
      Destroy (Cr);
      Surface_Destroy (Surface);
   end Save_Png;

end Limit_Sign;
