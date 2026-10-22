--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Strings.Unbounded;

with Cairo;
with Cairo.Image_Surface;
with Cairo.Png;
with Glib;
with Gtk.Drawing_Area;
with Gtk.Label;


package body Navigation is

   use Ada.Numerics.Elementary_Functions;
   use Ada.Strings.Unbounded;
   use Glib;
   use Road_Network;

   Size  : constant := 240;          --  minimap pixels
   Scale : constant := 0.45;         --  pixels per metre (about 270 m radius)

   Map   : Gtk.Drawing_Area.Gtk_Drawing_Area;
   Text  : Gtk.Label.Gtk_Label;

   Dest_Name    : Unbounded_String;
   Dest_X, Dest_Z : Float := 0.0;
   Has_Dest     : Boolean := False;
   Route        : Route_Vectors.Vector;
   Progress     : Natural := 0;      --  route segment we are on
   Reroute_Wait : Float := 0.0;
   Fixed        : Boolean := False;  --  a given route (Follow), not planned
   Arrived_Time : Float := 0.0;
   Me_X, Me_Z, Me_H : Float := 0.0;
   Shown_Text   : Unbounded_String;
   Visible      : Boolean := True;

   function Active return Boolean is (Has_Dest);

   type Marker is record
      X, Z : Float;
   end record;
   Markers : array (1 .. 64) of Marker;
   Marker_Count : Natural := 0;

   procedure Clear_Markers is
   begin
      Marker_Count := 0;
   end Clear_Markers;

   procedure Add_Marker (X, Z : Float) is
   begin
      if Marker_Count < Markers'Last then
         Marker_Count := Marker_Count + 1;
         Markers (Marker_Count) := (X, Z);
      end if;
   end Add_Marker;

   procedure Set_Destination (Name : String; X, Z : Float) is
   begin
      Dest_Name := To_Unbounded_String (Name);
      Dest_X := X;
      Dest_Z := Z;
      Has_Dest := True;
      Fixed := False;
      Route.Clear;
      Reroute_Wait := 0.0;
      Arrived_Time := 0.0;
   end Set_Destination;

   procedure Follow (Name : String; Path : Road_Network.Route_Vectors.Vector) is
   begin
      if Natural (Path.Length) < 2 then
         return;
      end if;
      Dest_Name := To_Unbounded_String (Name);
      Dest_X := Path.Last_Element.X;
      Dest_Z := Path.Last_Element.Z;
      Has_Dest := True;
      Fixed := True;
      Route := Path;
      Progress := 0;
      Arrived_Time := 0.0;
   end Follow;

   procedure Clear is
   begin
      Has_Dest := False;
      Fixed := False;
      Route.Clear;
   end Clear;

   procedure Show (On : Boolean) is
   begin
      Visible := On;
      if On then
         Map.Show;
      else
         Map.Hide;
         Text.Hide;
      end if;
   end Show;

   ---------------------------------------------------------------------------
   --  Following the route
   ---------------------------------------------------------------------------

   function Seg_Dist (I : Natural; X, Z : Float; T : out Float) return Float is
      A  : constant Route_Point := Route (I);
      B  : constant Route_Point := Route (I + 1);
      EX : constant Float := B.X - A.X;
      EZ : constant Float := B.Z - A.Z;
      L2 : constant Float := EX * EX + EZ * EZ;
   begin
      T := (if L2 > 1.0E-6
            then Float'Max (0.0, Float'Min (1.0, ((X - A.X) * EX + (Z - A.Z) * EZ) / L2))
            else 0.0);
      return Sqrt ((A.X + T * EX - X) ** 2 + (A.Z + T * EZ - Z) ** 2);
   end Seg_Dist;

   function Seg_Len (I : Natural) return Float is
     (Sqrt ((Route (I + 1).X - Route (I).X) ** 2 + (Route (I + 1).Z - Route (I).Z) ** 2));

   function Name_Of (W : Natural) return String is
     (To_String (Ways (W).Name));

   function Metres (D : Float) return String is
   begin
      if D >= 1000.0 then
         declare
            Tenths : constant Integer := Integer (D / 100.0);
            Img    : constant String := Integer'Image (Tenths / 10);
         begin
            return Img (Img'First + 1 .. Img'Last) & "." & Character'Val (48 + Tenths mod 10) & " km";
         end;
      else
         declare
            Img : constant String := Integer'Image (10 * Integer (D / 10.0));
         begin
            return Img (Img'First + 1 .. Img'Last) & " m";
         end;
      end if;
   end Metres;

   procedure Set_Text (Markup : String) is
   begin
      if To_String (Shown_Text) /= Markup then
         Shown_Text := To_Unbounded_String (Markup);
         if Markup = "" then
            Text.Hide;
         else
            Text.Set_Markup (Markup);
            if Visible then
               Text.Show;
            end if;
         end if;
      end if;
   end Set_Text;

   procedure Instruction (X, Z : Float) is
      T      : Float;
      D      : constant Float := Seg_Dist (Progress, X, Z, T);
      Ahead  : Float := (1.0 - T) * Seg_Len (Progress);   --  to the next route point
      Total  : Float := 0.0;
      Arrow  : Unbounded_String := To_Unbounded_String ("&#x2191;");
      Action : Unbounded_String := To_Unbounded_String ("Continue");
      Onto   : Unbounded_String;
      Found  : Boolean := False;
      Dist   : Float := 0.0;
      pragma Unreferenced (D);
   begin
      for K in Progress + 1 .. Route.Last_Index - 1 loop
         declare
            In_X  : constant Float := Route (K).X - Route (K - 1).X;
            In_Z  : constant Float := Route (K).Z - Route (K - 1).Z;
            Out_X : constant Float := Route (K + 1).X - Route (K).X;
            Out_Z : constant Float := Route (K + 1).Z - Route (K).Z;
            Li    : constant Float := Float'Max (Sqrt (In_X * In_X + In_Z * In_Z), 0.01);
            Lo    : constant Float := Float'Max (Sqrt (Out_X * Out_X + Out_Z * Out_Z), 0.01);
            --  positive: turning right (x east, z south, heading clockwise)
            Cross : constant Float := (In_X * Out_Z - In_Z * Out_X) / (Li * Lo);
            Dot   : constant Float := (In_X * Out_X + In_Z * Out_Z) / (Li * Lo);
            --  (two route points in the same place: no turn there)
            Angle : constant Float :=
              (if abs Cross + abs Dot < 1.0E-6 then 0.0
               else Arctan (Cross, Dot) * 180.0 / Ada.Numerics.Pi);
            New_Name : constant String := Name_Of (Route (K).Way);
            Old_Name : constant String := Name_Of (Route (K - 1).Way);
         begin
            if not Found
              and then ((New_Name /= Old_Name and then New_Name /= "" and then abs Angle > 20.0)
                        or else abs Angle > 55.0)
            then
               Found := True;
               Dist := Ahead;
               Onto := To_Unbounded_String (New_Name);
               if abs Angle < 35.0 then
                  Action := To_Unbounded_String (if Angle > 0.0 then "Keep right" else "Keep left");
                  Arrow := To_Unbounded_String (if Angle > 0.0 then "&#x2197;" else "&#x2196;");
               elsif abs Angle < 135.0 then
                  Action := To_Unbounded_String (if Angle > 0.0 then "Turn right" else "Turn left");
                  Arrow := To_Unbounded_String (if Angle > 0.0 then "&#x21B1;" else "&#x21B0;");
               else
                  Action := To_Unbounded_String ("Turn round");
                  Arrow := To_Unbounded_String ("&#x21BA;");
               end if;
            end if;
            Ahead := Ahead + Lo;
         end;
      end loop;
      Total := Ahead;
      if not Found then
         Dist := Ahead;
         Action := To_Unbounded_String ("Destination");
         Arrow := To_Unbounded_String ("&#x2691;");
         Onto := Dest_Name;
      end if;
      Set_Text
        ("<span font_family='sans' foreground='white' background='#1d3b72e0'>"
         & "<span size='xx-large' weight='bold'> " & To_String (Arrow) & " "
         & Metres (Dist) & " </span>" & ASCII.LF
         & "<span size='large'> " & To_String (Action)
         & (if Length (Onto) > 0 and then Found then " onto " & To_String (Onto) else "")
         & (if not Found then ": " & To_String (Onto) else "") & " </span>" & ASCII.LF
         & "<span size='small'> " & To_String (Dest_Name) & "  " & Metres (Total) & " </span>"
         & "</span>");
   end Instruction;

   procedure Update (X, Z, Heading : Float; Dt : Float; Route_Allowed : Boolean) is
   begin
      Me_X := X;
      Me_Z := Z;
      Me_H := Heading;
      if Visible then
         Map.Queue_Draw;
      end if;
      if not Has_Dest then
         if Arrived_Time > 0.0 then
            Arrived_Time := Arrived_Time - Dt;
            if Arrived_Time <= 0.0 then
               Set_Text ("");
            end if;
         else
            Set_Text ("");
         end if;
         return;
      end if;

      --  only arriving by car counts (not flying over it)
      if Route_Allowed and then not Fixed and then (X - Dest_X) ** 2 + (Z - Dest_Z) ** 2 < 30.0 ** 2 then
         Set_Text ("<span font_family='sans' size='x-large' weight='bold' foreground='white' "
                   & "background='#2f6b45e0'> &#x2691; You have arrived: "
                   & To_String (Dest_Name) & " </span>");
         Has_Dest := False;
         Route.Clear;
         Arrived_Time := 5.0;
         return;
      end if;
      if not Route_Allowed then
         Set_Text ("");
         return;
      end if;

      Reroute_Wait := Reroute_Wait - Dt;
      --  where are we on the route?
      if Natural (Route.Length) >= 2 then
         declare
            Best   : Float := Float'Last;
            Best_I : Natural := Progress;
            T      : Float;
         begin
            for I in Progress .. Natural'Min (Progress + 40, Route.Last_Index - 1) loop
               declare
                  D : constant Float := Seg_Dist (I, X, Z, T);
               begin
                  if D < Best then
                     Best := D;
                     Best_I := I;
                  end if;
               end;
            end loop;
            Progress := Best_I;
            if Best > 35.0 and then Reroute_Wait <= 0.0 and then not Fixed then
               Route.Clear;   --  off the route: plan again
            end if;
         end;
      end if;
      if Natural (Route.Length) < 2 and then Reroute_Wait <= 0.0 and then not Fixed then
         declare
            Found : Boolean;
         begin
            Find_Route (X, Z, Heading, Dest_X, Dest_Z, Route, Found);
            Progress := 0;
            Reroute_Wait := 2.0;
            if not Found then
               Route.Clear;
               Set_Text ("<span foreground='white' background='#7a1f1fe0'> No route to "
                         & To_String (Dest_Name) & " </span>");
               return;
            end if;
         end;
      end if;
      if Natural (Route.Length) >= 2 then
         Instruction (X, Z);
      end if;
   end Update;

   ---------------------------------------------------------------------------
   --  Minimap
   ---------------------------------------------------------------------------

   function Draw
     (Self : access Gtk.Widget.Gtk_Widget_Record'Class;
      Cr   : Cairo.Cairo_Context) return Boolean
   is
      pragma Unreferenced (Self);
      use Cairo;
      C  : constant Gdouble := Gdouble (Size) / 2.0;
      R  : constant Gdouble := C - 3.0;
      Pi : constant := Ada.Numerics.Pi;
      Ch : constant Float := Cos (Me_H);
      Sh : constant Float := Sin (Me_H);

      --  world (x, z) to minimap pixels: heading is up
      procedure To_Screen (X, Z : Float; SX, SY : out Gdouble) is
         DX : constant Float := X - Me_X;
         DZ : constant Float := Z - Me_Z;
      begin
         SX := C + Gdouble ((DX * Ch + DZ * Sh) * Scale);
         SY := C + Gdouble ((-DX * Sh + DZ * Ch) * Scale);
      end To_Screen;

      procedure Road (AX, AZ, BX, BZ, Width : Float; Named : Boolean) is
         X0, Y0, X1, Y1 : Gdouble;
      begin
         To_Screen (AX, AZ, X0, Y0);
         To_Screen (BX, BZ, X1, Y1);
         Set_Line_Width (Cr, Gdouble (Float'Max (1.5, Width * Scale * (if Named then 1.0 else 0.6))));
         Move_To (Cr, X0, Y0);
         Line_To (Cr, X1, Y1);
         Stroke (Cr);
      end Road;

      procedure Roads is new For_Segments_Near (Road);
   begin
      --  round map window
      Arc (Cr, C, C, R, 0.0, 2.0 * Pi);
      Set_Source_Rgba (Cr, 0.12, 0.13, 0.16, 0.78);
      Fill_Preserve (Cr);
      Clip (Cr);

      Set_Source_Rgba (Cr, 0.78, 0.78, 0.75, 0.9);
      Set_Line_Cap (Cr, Cairo_Line_Cap_Round);
      Roads (Me_X, Me_Z, Float (R) / Scale + 30.0);

      --  route ahead
      if Has_Dest and then Natural (Route.Length) >= 2 then
         declare
            SX, SY : Gdouble;
         begin
            Set_Source_Rgba (Cr, 0.25, 0.6, 1.0, 0.95);
            Set_Line_Width (Cr, 5.0);
            Set_Line_Join (Cr, Cairo_Line_Join_Round);
            To_Screen (Me_X, Me_Z, SX, SY);
            Move_To (Cr, SX, SY);
            for I in Progress + 1 .. Route.Last_Index loop
               To_Screen (Route (I).X, Route (I).Z, SX, SY);
               Line_To (Cr, SX, SY);
            end loop;
            Stroke (Cr);
         end;
      end if;
      --  saved places
      for I in 1 .. Marker_Count loop
         declare
            SX, SY : Gdouble;
         begin
            To_Screen (Markers (I).X, Markers (I).Z, SX, SY);
            if (SX - C) ** 2 + (SY - C) ** 2 < (R - 6.0) ** 2 then
               Move_To (Cr, SX, SY - 6.0);
               Line_To (Cr, SX + 5.0, SY);
               Line_To (Cr, SX, SY + 6.0);
               Line_To (Cr, SX - 5.0, SY);
               Close_Path (Cr);
               Set_Source_Rgba (Cr, 0.2, 0.85, 0.75, 1.0);
               Fill_Preserve (Cr);
               Set_Source_Rgba (Cr, 0.0, 0.0, 0.0, 0.6);
               Set_Line_Width (Cr, 1.0);
               Stroke (Cr);
            end if;
         end;
      end loop;

      --  destination flag (pinned to the rim when far away)
      if Has_Dest then
         declare
            SX, SY : Gdouble;
            DX, DY, L : Gdouble;
         begin
            To_Screen (Dest_X, Dest_Z, SX, SY);
            DX := SX - C;
            DY := SY - C;
            L := Gdouble (Sqrt (Float (DX * DX + DY * DY)));
            if L > R - 10.0 then
               SX := C + DX / L * (R - 10.0);
               SY := C + DY / L * (R - 10.0);
            end if;
            Arc (Cr, SX, SY, 7.0, 0.0, 2.0 * Pi);
            Set_Source_Rgba (Cr, 0.9, 0.15, 0.15, 1.0);
            Fill (Cr);
         end;
      end if;

      --  you: an arrow pointing up
      Move_To (Cr, C, C - 11.0);
      Line_To (Cr, C + 7.0, C + 8.0);
      Line_To (Cr, C, C + 4.0);
      Line_To (Cr, C - 7.0, C + 8.0);
      Close_Path (Cr);
      Set_Source_Rgba (Cr, 1.0, 0.85, 0.2, 1.0);
      Fill (Cr);

      --  north marker on the rim
      declare
         NX : constant Gdouble := C - Gdouble (Sh) * (R - 12.0);
         NY : constant Gdouble := C - Gdouble (Ch) * (R - 12.0);
      begin
         Arc (Cr, NX, NY, 9.0, 0.0, 2.0 * Pi);
         Set_Source_Rgba (Cr, 0.0, 0.0, 0.0, 0.7);
         Fill (Cr);
         Select_Font_Face (Cr, "Sans", Cairo_Font_Slant_Normal, Cairo_Font_Weight_Bold);
         Set_Font_Size (Cr, 12.0);
         Set_Source_Rgba (Cr, 1.0, 0.3, 0.25, 1.0);
         Move_To (Cr, NX - 4.5, NY + 4.5);
         Show_Text (Cr, "N");
      end;
      Reset_Clip (Cr);
      New_Path (Cr);
      Arc (Cr, C, C, R, 0.0, 2.0 * Pi);
      Set_Source_Rgba (Cr, 1.0, 1.0, 1.0, 0.8);
      Set_Line_Width (Cr, 2.0);
      Stroke (Cr);
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

   function Current_Text return String is (To_String (Shown_Text));

   function Create_Minimap return Gtk.Widget.Gtk_Widget is
   begin
      Gtk.Drawing_Area.Gtk_New (Map);
      Map.Set_Size_Request (Size, Size);
      Map.Set_Halign (Gtk.Widget.Align_End);
      Map.Set_Valign (Gtk.Widget.Align_End);
      Map.Set_Margin_End (12);
      Map.Set_Margin_Bottom (34);
      Map.On_Draw (Draw'Access);
      return Gtk.Widget.Gtk_Widget (Map);
   end Create_Minimap;

   function Create_Instructions return Gtk.Widget.Gtk_Widget is
   begin
      Gtk.Label.Gtk_New (Text);
      Text.Set_Halign (Gtk.Widget.Align_Start);
      Text.Set_Valign (Gtk.Widget.Align_Start);
      Text.Set_Margin_Start (14);
      Text.Set_Margin_Top (14);
      Text.Set_No_Show_All (True);
      return Gtk.Widget.Gtk_Widget (Text);
   end Create_Instructions;

end Navigation;
