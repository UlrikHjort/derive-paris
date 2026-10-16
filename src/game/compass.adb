--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;

with Cairo;
with Cairo.Image_Surface;
with Cairo.Png;
with Glib;
with Gtk.Box;
with Gtk.Drawing_Area;
with Gtk.Enums;
with Gtk.Label;

package body Compass is

   use Ada.Numerics.Elementary_Functions;
   use Glib;

   Size : constant := 120;

   Box   : Gtk.Box.Gtk_Box;
   Rose  : Gtk.Drawing_Area.Gtk_Drawing_Area;
   Text  : Gtk.Label.Gtk_Label;

   Heading : Float := 0.0;   --  radians, 0 = north, clockwise
   Shown_Heading : Integer := -1;
   Shown_Text    : String (1 .. 80) := (others => ' ');

   function Draw
     (Self : access Gtk.Widget.Gtk_Widget_Record'Class;
      Cr   : Cairo.Cairo_Context) return Boolean
   is
      pragma Unreferenced (Self);
      use Cairo;
      C  : constant Gdouble := Gdouble (Size) / 2.0;
      R  : constant Gdouble := C - 4.0;
      Pi : constant := Ada.Numerics.Pi;
   begin
      --  dial
      Arc (Cr, C, C, R, 0.0, 2.0 * Pi);
      Set_Source_Rgba (Cr, 0.0, 0.0, 0.0, 0.55);
      Fill_Preserve (Cr);
      Set_Source_Rgba (Cr, 1.0, 1.0, 1.0, 0.8);
      Set_Line_Width (Cr, 2.0);
      Stroke (Cr);

      --  the rose turns so that the way you look is up
      Save (Cr);
      Translate (Cr, C, C);
      Rotate (Cr, Gdouble (-Heading));
      for K in 0 .. 35 loop
         declare
            A     : constant Gdouble := Gdouble (K) * Pi / 18.0;
            Inner : constant Gdouble := (if K mod 9 = 0 then R - 14.0
                                         elsif K mod 3 = 0 then R - 9.0 else R - 5.0);
         begin
            Move_To (Cr, Inner * Gdouble (Sin (Float (A))), -Inner * Gdouble (Cos (Float (A))));
            Line_To (Cr, (R - 1.0) * Gdouble (Sin (Float (A))), -(R - 1.0) * Gdouble (Cos (Float (A))));
         end;
      end loop;
      Set_Line_Width (Cr, 1.5);
      Stroke (Cr);

      Select_Font_Face (Cr, "Sans", Cairo_Font_Slant_Normal, Cairo_Font_Weight_Bold);
      Set_Font_Size (Cr, 15.0);
      for K in 0 .. 3 loop
         declare
            Letter : constant String := (case K is
                                           when 0 => "N", when 1 => "E",
                                           when 2 => "S", when others => "W");
            A      : constant Gdouble := Gdouble (K) * Pi / 2.0;
            D      : constant Gdouble := R - 26.0;
         begin
            Save (Cr);
            Translate (Cr, D * Gdouble (Sin (Float (A))), -D * Gdouble (Cos (Float (A))));
            Rotate (Cr, Gdouble (Heading));   --  letters stay upright
            if K = 0 then
               Set_Source_Rgba (Cr, 1.0, 0.25, 0.2, 1.0);
            else
               Set_Source_Rgba (Cr, 1.0, 1.0, 1.0, 0.95);
            end if;
            Move_To (Cr, -5.0, 5.5);
            Show_Text (Cr, Letter);
            Restore (Cr);
         end;
      end loop;
      --  needle pointing north
      Move_To (Cr, 0.0, -(R - 32.0));
      Line_To (Cr, 5.0, 0.0);
      Line_To (Cr, -5.0, 0.0);
      Close_Path (Cr);
      Set_Source_Rgba (Cr, 0.9, 0.15, 0.1, 0.9);
      Fill (Cr);
      Move_To (Cr, 0.0, R - 32.0);
      Line_To (Cr, 5.0, 0.0);
      Line_To (Cr, -5.0, 0.0);
      Close_Path (Cr);
      Set_Source_Rgba (Cr, 0.85, 0.85, 0.85, 0.9);
      Fill (Cr);
      Restore (Cr);

      --  fixed index mark at the top: the way you look
      Move_To (Cr, C, 1.0);
      Line_To (Cr, C - 6.0, -8.0 + 13.0);
      Line_To (Cr, C + 6.0, -8.0 + 13.0);
      Close_Path (Cr);
      Set_Source_Rgba (Cr, 1.0, 0.85, 0.2, 1.0);
      Fill (Cr);
      return True;
   end Draw;

   procedure Save_Png (File_Name : String) is
      use Cairo;
      Surface : constant Cairo_Surface :=
        Cairo.Image_Surface.Create (Cairo.Image_Surface.Cairo_Format_ARGB32, Size, Size);
      Cr      : constant Cairo_Context := Create (Surface);
      Ok      : Boolean;
      Status  : Cairo_Status;
   begin
      Ok := Draw (null, Cr);
      Status := Cairo.Png.Write_To_Png (Surface, File_Name);
      pragma Unreferenced (Ok, Status);
      Destroy (Cr);
      Surface_Destroy (Surface);
   end Save_Png;

   function Create return Gtk.Widget.Gtk_Widget is
   begin
      Gtk.Box.Gtk_New_Vbox (Box, Homogeneous => False, Spacing => 4);
      Gtk.Drawing_Area.Gtk_New (Rose);
      Rose.Set_Size_Request (Size, Size);
      Rose.Set_Halign (Gtk.Widget.Align_End);
      Rose.On_Draw (Draw'Access);
      Gtk.Label.Gtk_New (Text);
      Text.Set_Justify (Gtk.Enums.Justify_Right);
      Text.Set_Halign (Gtk.Widget.Align_End);
      Box.Pack_Start (Rose, Expand => False, Fill => False);
      Box.Pack_Start (Text, Expand => False, Fill => False);
      Box.Set_Halign (Gtk.Widget.Align_End);
      Box.Set_Valign (Gtk.Widget.Align_Start);
      Box.Set_Margin_Top (10);
      Box.Set_Margin_End (10);
      return Gtk.Widget.Gtk_Widget (Box);
   end Create;

   function Fixed (V : Long_Float; Decimals : Natural) return String is
      Scale : constant Long_Float := 10.0 ** Decimals;
      I     : constant Long_Long_Integer := Long_Long_Integer (abs V * Scale);
      Whole : constant String := Long_Long_Integer'Image (I / Long_Long_Integer (Scale));
      Frac  : constant String := Long_Long_Integer'Image
        (Long_Long_Integer (Scale) + I mod Long_Long_Integer (Scale));
   begin
      return Whole (Whole'First + 1 .. Whole'Last) & "." & Frac (Frac'First + 2 .. Frac'Last);
   end Fixed;

   Points : constant array (0 .. 15) of String (1 .. 3) :=
     ("N  ", "NNE", "NE ", "ENE", "E  ", "ESE", "SE ", "SSE",
      "S  ", "SSW", "SW ", "WSW", "W  ", "WNW", "NW ", "NNW");

   procedure Update (Heading_Rad : Float; Lat, Lon : Long_Float; Altitude : Float) is
      Pi  : constant := Ada.Numerics.Pi;
      H   : Float := Heading_Rad - 2.0 * Pi * Float'Floor (Heading_Rad / (2.0 * Pi));
      Deg : Integer;
   begin
      H := Float'Max (0.0, H);
      Heading := H;
      Deg := Integer (H * 180.0 / Pi) mod 360;
      declare
         Point : constant String := Points (((Deg * 16 + 180) / 360) mod 16);
         Line  : constant String :=
           Fixed (abs Lat, 5) & (if Lat >= 0.0 then " N  " else " S  ")
           & Fixed (abs Lon, 5) & (if Lon >= 0.0 then " E" else " W") & ASCII.LF
           & Integer'Image (Deg) & "°  " & Point
           & (if Altitude >= 0.0 then "   alt" & Integer'Image (Integer (Altitude)) & " m" else "");
         Padded : String (1 .. 80) := (others => ' ');
      begin
         Padded (1 .. Integer'Min (80, Line'Length)) := Line (Line'First .. Line'First + Integer'Min (80, Line'Length) - 1);
         if Deg /= Shown_Heading then
            Shown_Heading := Deg;
            Rose.Queue_Draw;
         end if;
         if Padded /= Shown_Text then
            Shown_Text := Padded;
            Text.Set_Markup
              ("<span font_family='monospace' foreground='white' background='#00000088'> "
               & Line & " </span>");
         end if;
      end;
   end Update;

end Compass;
