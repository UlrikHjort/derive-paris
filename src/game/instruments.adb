--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics;

with Cairo;
with Cairo.Image_Surface;
with Cairo.Png;
with Glib;
with Gtk.Drawing_Area;
with Gtkada.Types;

package body Instruments is

   use Glib;
   use Cairo;

   Width  : constant := 250;
   Height : constant := 150;
   Red_Line : constant := 6500.0;
   Max_Rpm  : constant := 7500.0;

   Area  : Gtk.Drawing_Area.Gtk_Drawing_Area;
   Now   : Reading;
   Drawn : Reading;

   procedure Text (Cr : Cairo_Context; X, Y : Gdouble; S : String; Size : Gdouble;
                   Bold : Boolean := False; Centre : Boolean := True) is
      E : aliased Cairo_Text_Extents;
      P : Gtkada.Types.Chars_Ptr := Gtkada.Types.New_String (S);
   begin
      Select_Font_Face (Cr, "Sans", Cairo_Font_Slant_Normal,
                        (if Bold then Cairo_Font_Weight_Bold else Cairo_Font_Weight_Normal));
      Set_Font_Size (Cr, Size);
      Text_Extents (Cr, P, E'Access);
      Gtkada.Types.Free (P);
      Move_To (Cr, (if Centre then X - E.Width / 2.0 - E.X_Bearing else X),
               Y + E.Height / 2.0);
      Show_Text (Cr, S);
   end Text;

   procedure Rounded (Cr : Cairo_Context; X, Y, W, H, R : Gdouble) is
      Pi : constant := Ada.Numerics.Pi;
   begin
      New_Path (Cr);
      Arc (Cr, X + W - R, Y + R, R, -Pi / 2.0, 0.0);
      Arc (Cr, X + W - R, Y + H - R, R, 0.0, Pi / 2.0);
      Arc (Cr, X + R, Y + H - R, R, Pi / 2.0, Pi);
      Arc (Cr, X + R, Y + R, R, Pi, 1.5 * Pi);
      Close_Path (Cr);
   end Rounded;

   --  The shifter gate: 1 3 5 on top, 2 4 6 below, R right of 6
   Col_X : constant array (1 .. 4) of Gdouble := (28.0, 58.0, 88.0, 118.0);
   Top_Y : constant := 30.0;
   Mid_Y : constant := 60.0;
   Low_Y : constant := 90.0;

   procedure Gear_Spot (G : Integer; X, Y : out Gdouble) is
   begin
      case G is
         when 1 | 3 | 5 => X := Col_X ((G + 1) / 2); Y := Top_Y;
         when 2 | 4 | 6 => X := Col_X (G / 2); Y := Low_Y;
         when -1 => X := Col_X (4); Y := Low_Y;
         when others => X := Col_X (2) + 15.0; Y := Mid_Y;   --  neutral
      end case;
   end Gear_Spot;

   procedure Paint (Cr : Cairo_Context) is
      R : constant Reading := Now;
      Pi : constant := Ada.Numerics.Pi;
   begin
      Rounded (Cr, 1.0, 1.0, Gdouble (Width) - 2.0, Gdouble (Height) - 2.0, 12.0);
      Set_Source_Rgba (Cr, 0.0, 0.0, 0.0, 0.55);
      Fill_Preserve (Cr);
      Set_Source_Rgba (Cr, 1.0, 1.0, 1.0, 0.35);
      Set_Line_Width (Cr, 1.5);
      Stroke (Cr);

      if R.Manual then
         --  the gate
         Set_Source_Rgba (Cr, 0.75, 0.75, 0.78, 0.9);
         Set_Line_Width (Cr, 4.0);
         Set_Line_Cap (Cr, Cairo_Line_Cap_Round);
         for C in 1 .. 3 loop
            Move_To (Cr, Col_X (C), Top_Y);
            Line_To (Cr, Col_X (C), Low_Y);
         end loop;
         Move_To (Cr, Col_X (4), Mid_Y);
         Line_To (Cr, Col_X (4), Low_Y);
         Move_To (Cr, Col_X (1), Mid_Y);
         Line_To (Cr, Col_X (4), Mid_Y);
         Stroke (Cr);
         --  the numbers
         for G in -1 .. 6 loop
            if G /= 0 then
               declare
                  X, Y : Gdouble;
                  Label : constant String :=
                    (if G = -1 then "R" else Integer'Image (G) (2 .. 2));
               begin
                  Gear_Spot (G, X, Y);
                  Set_Source_Rgba (Cr, 1.0, 1.0, 1.0, (if G = R.Gear then 1.0 else 0.65));
                  Text (Cr, X, (if Y = Top_Y then Y - 15.0 else Y + 15.0), Label, 13.0,
                        Bold => G = R.Gear);
               end;
            end if;
         end loop;
         --  the knob
         declare
            X, Y : Gdouble;
         begin
            --  where the lever is; red when that gear did not go in
            Gear_Spot (R.Lever, X, Y);
            New_Path (Cr);
            Arc (Cr, X, Y, 9.0, 0.0, 2.0 * Pi);
            if R.Grinding then
               Set_Source_Rgba (Cr, 0.95, 0.2, 0.15, 1.0);
            else
               Set_Source_Rgba (Cr, 1.0, 0.82, 0.2, 1.0);
            end if;
            Fill_Preserve (Cr);
            Set_Source_Rgba (Cr, 0.0, 0.0, 0.0, 0.7);
            Set_Line_Width (Cr, 1.5);
            Stroke (Cr);
         end;
      else
         --  automatic: R N D, and the gear it is in
         for K in 0 .. 2 loop
            declare
               Y   : constant Gdouble := 30.0 + Gdouble (K) * 34.0;
               Sel : constant Boolean :=
                 (case K is when 0 => R.Gear = -1, when 1 => R.Gear = 0,
                             when others => R.Gear >= 1);
            begin
               if Sel then
                  Rounded (Cr, 18.0, Y - 14.0, 30.0, 28.0, 6.0);
                  Set_Source_Rgba (Cr, 1.0, 0.82, 0.2, 1.0);
                  Fill (Cr);
                  Set_Source_Rgba (Cr, 0.0, 0.0, 0.0, 1.0);
               else
                  Set_Source_Rgba (Cr, 1.0, 1.0, 1.0, 0.6);
               end if;
               Text (Cr, 33.0, Y, (case K is when 0 => "R", when 1 => "N", when others => "D"),
                     17.0, Bold => True);
            end;
         end loop;
         if R.Gear >= 1 then
            Set_Source_Rgba (Cr, 1.0, 1.0, 1.0, 1.0);
            Text (Cr, 85.0, 64.0, Integer'Image (R.Gear) (2 .. 2), 44.0, Bold => True);
            Set_Source_Rgba (Cr, 1.0, 1.0, 1.0, 0.6);
            Text (Cr, 85.0, 96.0, "gear", 11.0);
         end if;
      end if;

      --  speed
      Set_Source_Rgba (Cr, 1.0, 1.0, 1.0, 1.0);
      Text (Cr, (if R.Pedals then 168.0 else 190.0), 52.0,
            Integer'Image (Integer (R.Kmh)) (2 .. Integer'Image (Integer (R.Kmh))'Last),
            34.0, Bold => True);
      Set_Source_Rgba (Cr, 1.0, 1.0, 1.0, 0.6);
      Text (Cr, (if R.Pedals then 168.0 else 190.0), 82.0, "km/h", 11.0);

      --  pedals: clutch, brake, throttle
      if R.Pedals then
         declare
            Amount : constant array (1 .. 3) of Float := (R.Clutch, R.Brake, R.Throttle);
            Names  : constant array (1 .. 3) of String (1 .. 1) := ("C", "B", "T");
            Colour : constant array (1 .. 3, 1 .. 3) of Gdouble :=
              ((0.4, 0.65, 1.0), (1.0, 0.3, 0.25), (0.35, 0.9, 0.4));
         begin
            for P in 1 .. 3 loop
               declare
                  X : constant Gdouble := 200.0 + Gdouble (P - 1) * 16.0;
                  H : constant Gdouble := 70.0;
                  F : constant Gdouble := Gdouble (Float'Max (0.0, Float'Min (1.0, Amount (P))));
               begin
                  Rectangle (Cr, X, 18.0, 10.0, H);
                  Set_Source_Rgba (Cr, 1.0, 1.0, 1.0, 0.15);
                  Fill (Cr);
                  Rectangle (Cr, X, 18.0 + H * (1.0 - F), 10.0, H * F);
                  Set_Source_Rgba (Cr, Colour (P, 1), Colour (P, 2), Colour (P, 3), 1.0);
                  Fill (Cr);
                  Set_Source_Rgba (Cr, 1.0, 1.0, 1.0, 0.6);
                  Text (Cr, X + 5.0, 98.0, Names (P), 10.0);
               end;
            end loop;
         end;
      end if;

      --  rev counter
      declare
         X0 : constant Gdouble := 14.0;
         X1 : constant Gdouble := Gdouble (Width) - 14.0;
         Y  : constant Gdouble := 124.0;
         function At_Rpm (V : Float) return Gdouble is
           (X0 + (X1 - X0) * Gdouble (Float'Min (1.0, V / Max_Rpm)));
      begin
         Rectangle (Cr, X0, Y, X1 - X0, 10.0);
         Set_Source_Rgba (Cr, 1.0, 1.0, 1.0, 0.12);
         Fill (Cr);
         Rectangle (Cr, At_Rpm (Red_Line), Y, X1 - At_Rpm (Red_Line), 10.0);
         Set_Source_Rgba (Cr, 0.9, 0.15, 0.1, 0.45);
         Fill (Cr);
         Rectangle (Cr, X0, Y, At_Rpm (R.Rpm) - X0, 10.0);
         if R.Rpm >= Red_Line then
            Set_Source_Rgba (Cr, 1.0, 0.25, 0.15, 1.0);
         else
            Set_Source_Rgba (Cr, 1.0, 1.0, 1.0, 0.85);
         end if;
         Fill (Cr);
         Set_Source_Rgba (Cr, 1.0, 1.0, 1.0, 0.55);
         for K in 1 .. 7 loop
            Text (Cr, At_Rpm (Float (K) * 1000.0), Y - 7.0, Integer'Image (K) (2 .. 2), 8.0);
         end loop;
         Text (Cr, X0 + 2.0, Y + 18.0, "rpm x 1000", 8.0, Centre => False);
      end;
   end Paint;

   function Draw
     (Self : access Gtk.Widget.Gtk_Widget_Record'Class;
      Cr   : Cairo_Context) return Boolean
   is
      pragma Unreferenced (Self);
   begin
      Paint (Cr);
      Drawn := Now;
      return True;
   end Draw;

   function Create return Gtk.Widget.Gtk_Widget is
   begin
      Gtk.Drawing_Area.Gtk_New (Area);
      Area.Set_Size_Request (Width, Height + 14);
      Area.Set_Halign (Gtk.Widget.Align_Start);
      Area.Set_Valign (Gtk.Widget.Align_End);
      Area.Set_Margin_Start (10);
      Area.Set_Margin_Bottom (36);
      Area.On_Draw (Draw'Access);
      return Gtk.Widget.Gtk_Widget (Area);
   end Create;

   procedure Update (R : Reading) is
   begin
      Now := R;
      if R.Gear /= Drawn.Gear or else R.Manual /= Drawn.Manual
        or else R.Grinding /= Drawn.Grinding or else R.Pedals /= Drawn.Pedals
        or else R.Lever /= Drawn.Lever
        or else Integer (R.Kmh) /= Integer (Drawn.Kmh)
        or else abs (R.Rpm - Drawn.Rpm) > 60.0
        or else abs (R.Clutch - Drawn.Clutch) > 0.02
        or else abs (R.Brake - Drawn.Brake) > 0.02
        or else abs (R.Throttle - Drawn.Throttle) > 0.02
      then
         Area.Queue_Draw;
      end if;
   end Update;

   procedure Save_Png (File_Name : String) is
      Surface : constant Cairo_Surface :=
        Cairo.Image_Surface.Create (Cairo.Image_Surface.Cairo_Format_ARGB32, Width, Height);
      Cr      : constant Cairo_Context := Create (Surface);
      Status  : Cairo_Status;
   begin
      Paint (Cr);
      Status := Cairo.Png.Write_To_Png (Surface, File_Name);
      pragma Unreferenced (Status);
      Destroy (Cr);
      Surface_Destroy (Surface);
   end Save_Png;

end Instruments;
