--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Strings.Fixed;

with Cairo;
with Glib;
with Gtk.Drawing_Area;

with River;

package body Altimeter is

   use Glib;
   use Cairo;

   W : constant := 96;
   H : constant := 300;
   Span : constant := 40.0;   --  metres shown on the tape

   Area : Gtk.Drawing_Area.Gtk_Drawing_Area;
   Shown : Boolean := False;
   Alt, Rate : Float := 0.0;
   Water : Boolean := False;
   Drawn_Alt, Drawn_Rate : Integer := -9999;
   Drawn_Water : Boolean := False;

   function Img (V : Float) return String is
      --  one decimal below 10 m, whole metres above
      T : constant Integer := Integer (V * 10.0);
   begin
      if abs V < 10.0 then
         return Ada.Strings.Fixed.Trim (Integer'Image (T / 10), Ada.Strings.Left) & "."
           & Ada.Strings.Fixed.Trim (Integer'Image (abs T mod 10), Ada.Strings.Left);
      end if;
      return Ada.Strings.Fixed.Trim (Integer'Image (Integer (V)), Ada.Strings.Left);
   end Img;

   function Draw
     (Self : access Gtk.Widget.Gtk_Widget_Record'Class;
      Cr   : Cairo_Context) return Boolean
   is
      pragma Unreferenced (Self);
      X0 : constant Gdouble := 10.0;
      TW : constant Gdouble := 34.0;            --  the tape's width
      Y0 : constant Gdouble := 18.0;            --  its top
      TH : constant Gdouble := Gdouble (H) - 60.0;
      --  the tape: 0 at the bottom, Span at the top; the height you are at
      --  marked by a pointer (higher than Span: pinned to the top)
      --  the low part stretched: 0 .. 10 m fill the lower 55 %, so the
      --  band under the bridges is easy to read
      function Y_Of (M : Float) return Gdouble is
         C : constant Float := Float'Max (0.0, Float'Min (Span, M));
         F : constant Float := (if C <= 10.0 then 0.55 * C / 10.0
                                else 0.55 + 0.45 * (C - 10.0) / (Span - 10.0));
      begin
         return Y0 + TH * Gdouble (1.0 - F);
      end Y_Of;
   begin
      --  the case
      Rectangle (Cr, 2.0, 2.0, Gdouble (W) - 4.0, Gdouble (H) - 4.0);
      Set_Source_Rgba (Cr, 0.0, 0.0, 0.0, 0.55);
      Fill (Cr);
      Rectangle (Cr, X0, Y0, TW, TH);
      Set_Source_Rgba (Cr, 0.12, 0.13, 0.16, 0.9);
      Fill (Cr);
      --  the water, and the band under the bridges
      if Water then
         Rectangle (Cr, X0, Y_Of (0.0) - 3.0, TW, 3.0);
         Set_Source_Rgba (Cr, 0.2, 0.45, 0.85, 1.0);
         Fill (Cr);
         Rectangle (Cr, X0, Y_Of (River.Gap_Top), TW, Y_Of (River.Lowest) - Y_Of (River.Gap_Top));
         Set_Source_Rgba (Cr, 0.2, 0.85, 0.35, 0.55);
         Fill (Cr);
         --  the bridges' undersides
         Rectangle (Cr, X0, Y_Of (River.Depth - River.Deck_Under), TW, 2.0);
         Set_Source_Rgba (Cr, 0.9, 0.3, 0.2, 1.0);
         Fill (Cr);
      else
         Rectangle (Cr, X0, Y_Of (0.0) - 3.0, TW, 3.0);
         Set_Source_Rgba (Cr, 0.55, 0.42, 0.25, 1.0);
         Fill (Cr);
      end if;
      --  the scale: a tick every 2 m, a number every 10
      Set_Source_Rgba (Cr, 1.0, 1.0, 1.0, 0.85);
      Set_Line_Width (Cr, 1.0);
      Select_Font_Face (Cr, "Sans", Cairo_Font_Slant_Normal, Cairo_Font_Weight_Normal);
      Set_Font_Size (Cr, 10.0);
      --  ticks: every metre up to 10, every 5 above; numbers at 0, 2 .. 10, 20, 30, 40
      for M in 0 .. Integer (Span) loop
         if M <= 10 or else M mod 5 = 0 then
            declare
               Y : constant Gdouble := Y_Of (Float (M));
               Num : constant Boolean := (M <= 10 and then M mod 2 = 0) or else M mod 10 = 0;
               L : constant Gdouble := (if Num then 12.0 else 6.0);
            begin
               Move_To (Cr, X0 + TW - L, Y);
               Line_To (Cr, X0 + TW, Y);
               Stroke (Cr);
               if Num then
                  Move_To (Cr, X0 + TW + 4.0, Y + 4.0);
                  Show_Text (Cr, Ada.Strings.Fixed.Trim (Integer'Image (M), Ada.Strings.Left));
               end if;
            end;
         end if;
      end loop;
      --  the pointer: yellow, green inside the band over the water
      declare
         Y : constant Gdouble := Y_Of (Alt);
         In_Band : constant Boolean := Water and then Alt >= River.Lowest and then Alt <= River.Gap_Top;
      begin
         if In_Band then
            Set_Source_Rgba (Cr, 0.3, 1.0, 0.45, 1.0);
         elsif Water and then Alt < River.Gap_Top + 2.0 then
            Set_Source_Rgba (Cr, 1.0, 0.35, 0.25, 1.0);
         else
            Set_Source_Rgba (Cr, 1.0, 0.85, 0.2, 1.0);
         end if;
         Move_To (Cr, X0 - 6.0, Y - 6.0);
         Line_To (Cr, X0 + 6.0, Y);
         Line_To (Cr, X0 - 6.0, Y + 6.0);
         Close_Path (Cr);
         Fill (Cr);
         Rectangle (Cr, X0, Y - 1.0, TW, 2.0);
         Fill (Cr);
      end;
      --  the number, and the climb
      Select_Font_Face (Cr, "Sans", Cairo_Font_Slant_Normal, Cairo_Font_Weight_Bold);
      Set_Font_Size (Cr, 20.0);
      Set_Source_Rgba (Cr, 1.0, 1.0, 1.0, 1.0);
      Move_To (Cr, 10.0, Gdouble (H) - 22.0);
      Show_Text (Cr, Img (Alt) & " m");
      Set_Font_Size (Cr, 11.0);
      Select_Font_Face (Cr, "Sans", Cairo_Font_Slant_Normal, Cairo_Font_Weight_Normal);
      Set_Source_Rgba (Cr, 0.8, 0.85, 0.9, 1.0);
      Move_To (Cr, 10.0, Gdouble (H) - 8.0);
      Show_Text (Cr, (if Rate >= 0.0 then "+" else "") & Img (Rate) & " m/s");
      Move_To (Cr, 12.0, 13.0);
      Show_Text (Cr, (if Water then "ALT water" else "ALT ground"));
      return True;
   end Draw;

   function Create return Gtk.Widget.Gtk_Widget is
   begin
      Gtk.Drawing_Area.Gtk_New (Area);
      Area.Set_Size_Request (W, H);
      Area.On_Draw (Draw'Access);
      Area.Set_No_Show_All (True);
      return Gtk.Widget.Gtk_Widget (Area);
   end Create;

   procedure Set (Visible : Boolean; Height, Climb : Float; Over_Water : Boolean) is
      use type Gtk.Drawing_Area.Gtk_Drawing_Area;
   begin
      if Area = null then
         return;
      end if;
      if Visible /= Shown then
         Shown := Visible;
         if Visible then
            Area.Show;
         else
            Area.Hide;
         end if;
      end if;
      Alt := Height;
      Rate := Climb;
      Water := Over_Water;
      --  redraw only when what it shows has changed
      if Visible and then (Integer (Alt * 10.0) /= Drawn_Alt or else Integer (Rate * 10.0) /= Drawn_Rate
                           or else Water /= Drawn_Water)
      then
         Drawn_Alt := Integer (Alt * 10.0);
         Drawn_Rate := Integer (Rate * 10.0);
         Drawn_Water := Water;
         Area.Queue_Draw;
      end if;
   end Set;

end Altimeter;
