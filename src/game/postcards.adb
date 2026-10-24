--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Characters.Handling;
with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Numerics.Elementary_Functions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Glib.Convert;
with Gtk.Box;
with Gtk.Enums;
with Gtk.Image;
with Gtk.Label;

with Geo;
with Photo;
with Sound;
with Terrain;
with World;

package body Postcards is

   use Ada.Strings.Unbounded;
   use Ada.Numerics.Elementary_Functions;
   use Math3D;

   type Card is record
      Name, Text : Unbounded_String;
      X, Z, Radius : Float := 0.0;
      Got : Boolean := False;
      Bought : Boolean := False;   --  from a shop, not a place to find
   end record;
   package Card_Vectors is new Ada.Containers.Vectors (Positive, Card);
   Cards : Card_Vectors.Vector;

   Pending   : Natural := 0;   --  the card whose picture is to be taken
   Shown     : Natural := 0;   --  the page open in the album (an index in Cards)
   Fresh     : Unbounded_String;
   Box       : Gtk.Box.Gtk_Vbox;
   Picture   : Gtk.Image.Gtk_Image;
   Words     : Gtk.Label.Gtk_Label;
   Open      : Boolean := False;

   function Folder return String is
     (Ada.Environment_Variables.Value ("HOME", ".") & "/.derive_postcards");

   --  a file name from the card's name: letters and digits only
   function Slug (S : String) return String is
      R : String (S'Range);
      N : Natural := R'First - 1;
   begin
      for C of S loop
         if Ada.Characters.Handling.Is_Alphanumeric (C) then
            N := N + 1;
            R (N) := Ada.Characters.Handling.To_Lower (C);
         elsif N >= R'First and then R (N) /= '_' then
            N := N + 1;
            R (N) := '_';
         end if;
      end loop;
      return R (R'First .. N);
   end Slug;

   function Picture_Of (C : Card) return String is
     (Folder & "/" & Slug (To_String (C.Name)) & ".png");

   --  the bought cards: one per line, name <tab> words
   function Bought_File return String is (Folder & "/bought.txt");

   --  How many places there are to find (the bought cards are extra)
   function Total return Natural is
      N : Natural := 0;
   begin
      for C of Cards loop
         if not C.Bought then
            N := N + 1;
         end if;
      end loop;
      return N;
   end Total;

   function Collected return Natural is
      N : Natural := 0;
   begin
      for C of Cards loop
         if C.Got and then not C.Bought then
            N := N + 1;
         end if;
      end loop;
      return N;
   end Collected;

   procedure Load is
      F : Ada.Text_IO.File_Type;
      Cur : Card;
      Have : Boolean := False;
      procedure Finish is
      begin
         if Have and then Length (Cur.Name) > 0 then
            Cards.Append (Cur);
         end if;
         Cur := (others => <>);
      end Finish;
   begin
      Cards.Clear;
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, "data/postcards.txt");
      while not Ada.Text_IO.End_Of_File (F) loop
         declare
            L : constant String := Ada.Text_IO.Get_Line (F);
            Sp : constant Natural := Ada.Strings.Fixed.Index (L, " ");
            W : constant String := (if Sp > 0 then L (L'First .. Sp - 1) else L);
            Rest : constant String := (if Sp > 0 then L (Sp + 1 .. L'Last) else "");
         begin
            if L'Length = 0 or else L (L'First) = '#' then
               null;
            elsif L (L'First) = '[' then
               Finish;
               Have := True;
            elsif W = "name" then
               Cur.Name := To_Unbounded_String (Rest);
            elsif W = "text" then
               Cur.Text := To_Unbounded_String (Rest);
            elsif W = "at" then
               declare
                  S1 : constant Natural := Ada.Strings.Fixed.Index (Rest, " ");
                  S2 : constant Natural := Ada.Strings.Fixed.Index (Rest, " ", S1 + 1);
                  X, Z : Long_Float;
               begin
                  Geo.To_Local (Long_Float'Value (Rest (Rest'First .. S1 - 1)),
                                Long_Float'Value (Rest (S1 + 1 .. S2 - 1)), X, Z);
                  Cur.X := Float (X);
                  Cur.Z := Float (Z);
                  Cur.Radius := Float'Value (Rest (S2 + 1 .. Rest'Last));
               end;
            end if;
         exception
            when Constraint_Error => null;   --  a line we do not understand
         end;
      end loop;
      Finish;
      Ada.Text_IO.Close (F);
      --  the bought ones
      begin
         Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Bought_File);
         while not Ada.Text_IO.End_Of_File (F) loop
            declare
               L : constant String := Ada.Text_IO.Get_Line (F);
               T : constant Natural := Ada.Strings.Fixed.Index (L, (1 => ASCII.HT));
            begin
               if T > L'First then
                  Cards.Append ((Name => To_Unbounded_String (L (L'First .. T - 1)),
                                 Text => To_Unbounded_String (L (T + 1 .. L'Last)),
                                 Bought => True, others => <>));
               end if;
            end;
         end loop;
         Ada.Text_IO.Close (F);
      exception
         when others =>
            if Ada.Text_IO.Is_Open (F) then
               Ada.Text_IO.Close (F);
            end if;
      end;
      --  the ones already in the album
      for C of Cards loop
         C.Got := Ada.Directories.Exists (Picture_Of (C));
      end loop;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (F) then
            Ada.Text_IO.Close (F);
         end if;
   end Load;

   Every : Natural := 0;   --  (the view is checked now and then)

   procedure Update (Cam, Look : Vec3; Allowed : Boolean) is
      LX : constant Float := Look.X - Cam.X;
      LZ : constant Float := Look.Z - Cam.Z;
      LL : constant Float := Sqrt (LX * LX + LZ * LZ);
   begin
      Every := (Every + 1) mod 10;
      if not Allowed or else Pending /= 0 or else LL < 0.01 or else Every /= 0 then
         return;
      end if;
      for I in Cards.First_Index .. Cards.Last_Index loop
         declare
            C  : Card renames Cards (I);
            DX : constant Float := C.X - Cam.X;
            DZ : constant Float := C.Z - Cam.Z;
            D  : constant Float := Sqrt (DX * DX + DZ * DZ);
            Up : constant Float := Cam.Y - Terrain.Height (C.X, C.Z);
         begin
            --  near, not too high above it, and before you (within 30 degrees)
            if not C.Got and then not C.Bought and then D < C.Radius and then D > 12.0
              and then Up < C.Radius
              and then (DX * LX + DZ * LZ) / (D * LL) > 0.866
              --  and in sight: no houses in between (its own walls may be
              --  a good way from its middle)
              and then World.Ray_Free (Cam, (C.X, Terrain.Height (C.X, C.Z) + 12.0, C.Z)) * D
                         > D - Float'Max (40.0, 0.45 * C.Radius)
            then
               Pending := I;
               return;
            end if;
         end;
      end loop;
   end Update;

   function Want_Picture return Boolean is (Pending /= 0);

   procedure Take_Picture (Width, Height : Natural) is
   begin
      if Pending = 0 then
         return;
      end if;
      begin
         Ada.Directories.Create_Path (Folder);
      exception
         when others =>
            Pending := 0;
            return;
      end;
      declare
         C : Card renames Cards (Pending);
      begin
         Photo.Take_As (Width, Height, Picture_Of (C), 640);
         C.Got := True;
         Sound.Shutter;
         Fresh := To_Unbounded_String
           (if C.Bought then "Bought a postcard: " & To_String (C.Name) & "  (F4 for the album)" else
            "Postcard: " & To_String (C.Name) & "  ("
            & Ada.Strings.Fixed.Trim (Natural'Image (Collected), Ada.Strings.Left) & "/"
            & Ada.Strings.Fixed.Trim (Natural'Image (Total), Ada.Strings.Left) & ", F4 for the album)");
         Shown := Pending;
      end;
      Pending := 0;
   end Take_Picture;

   procedure Buy (Name, Text : String) is
      F : Ada.Text_IO.File_Type;
   begin
      for I in Cards.First_Index .. Cards.Last_Index loop
         if Cards (I).Bought and then To_String (Cards (I).Name) = Name then
            Pending := I;   --  bought before: a new print
            return;
         end if;
      end loop;
      Cards.Append ((Name => To_Unbounded_String (Name), Text => To_Unbounded_String (Text),
                     Bought => True, others => <>));
      Pending := Cards.Last_Index;
      begin
         Ada.Directories.Create_Path (Folder);
         if Ada.Directories.Exists (Bought_File) then
            Ada.Text_IO.Open (F, Ada.Text_IO.Append_File, Bought_File);
         else
            Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Bought_File);
         end if;
         Ada.Text_IO.Put_Line (F, Name & ASCII.HT & Text);
         Ada.Text_IO.Close (F);
      exception
         when others =>
            if Ada.Text_IO.Is_Open (F) then
               Ada.Text_IO.Close (F);
            end if;
      end;
   end Buy;

   function News return String is
      S : constant String := To_String (Fresh);
   begin
      Fresh := Null_Unbounded_String;
      return S;
   end News;

   ---------------------------------------------------------------------------
   --  The album

   function Album return Gtk.Widget.Gtk_Widget is
      use type Gtk.Box.Gtk_Vbox;
   begin
      if Box /= null then
         return Gtk.Widget.Gtk_Widget (Box);
      end if;
      Gtk.Box.Gtk_New_Vbox (Box, Spacing => 10);
      Gtk.Image.Gtk_New (Picture);
      Gtk.Label.Gtk_New (Words);
      Words.Set_Line_Wrap (True);
      Words.Set_Max_Width_Chars (62);
      Words.Set_Justify (Gtk.Enums.Justify_Left);
      Box.Pack_Start (Picture, Expand => False, Fill => False);
      Box.Pack_Start (Words, Expand => False, Fill => False);
      Box.Set_Halign (Gtk.Widget.Align_Center);
      Box.Set_Valign (Gtk.Widget.Align_Center);
      Box.Set_No_Show_All (True);
      return Gtk.Widget.Gtk_Widget (Box);
   end Album;

   function Album_Open return Boolean is (Open);

   --  the next collected card from From, one way or the other (0: none)
   function Next_Got (From : Integer; Step : Integer) return Natural is
      I : Integer := From;
   begin
      for K in 1 .. Total loop
         I := I + Step;
         if I > Cards.Last_Index then
            I := Cards.First_Index;
         elsif I < Cards.First_Index then
            I := Cards.Last_Index;
         end if;
         if Cards (I).Got then
            return I;
         end if;
      end loop;
      return 0;
   end Next_Got;

   procedure Show_Page is
      function Esc (S : String) return String renames Glib.Convert.Escape_Text;
      N : constant String := Ada.Strings.Fixed.Trim (Natural'Image (Collected), Ada.Strings.Left);
      T : constant String := Ada.Strings.Fixed.Trim (Natural'Image (Total), Ada.Strings.Left);
   begin
      if Shown = 0 or else not Cards (Shown).Got then
         Shown := Next_Got (Cards.Last_Index, 1);
      end if;
      if Shown = 0 then
         Picture.Clear;
         Picture.Hide;
         Words.Set_Markup
           ("<b><span size='large' foreground='#ffd27a'>Your postcards</span></b>" & ASCII.LF & ASCII.LF
            & "No postcards yet: " & T & " famous places to find." & ASCII.LF
            & "Come near one, with it before you, and its picture is taken." & ASCII.LF & ASCII.LF
            & "<span foreground='#aab'>F4 or Esc: close</span>");
         return;
      end if;
      declare
         C : Card renames Cards (Shown);
         Page : Natural := 0;
      begin
         for I in Cards.First_Index .. Shown loop
            if Cards (I).Got then
               Page := Page + 1;
            end if;
         end loop;
         Picture.Set (Picture_Of (C));
         Picture.Show;
         Words.Set_Markup
           ("<b><span size='x-large' font_family='serif' foreground='#ffd27a'>" & Esc (To_String (C.Name))
            & "</span></b>" & ASCII.LF & ASCII.LF
            & "<span font_family='serif' size='large'>" & Esc (To_String (C.Text)) & "</span>" & ASCII.LF & ASCII.LF
            & "<span foreground='#aab'>"
            & (if C.Bought then "a postcard you bought"
               else "card" & Natural'Image (Page) & " of the " & N & " you have found, of " & T)
            & "      Left / Right: turn the page      F4 or Esc: close</span>");
      end;
   end Show_Page;

   procedure Toggle_Album is
   begin
      Open := not Open;
      if Open then
         Show_Page;
         Box.Show;
         Words.Show;
      else
         Box.Hide;
      end if;
   end Toggle_Album;

   function Album_Key (Key : Natural) return Boolean is
   begin
      if not Open then
         return False;
      end if;
      case Key is
         when 16#FF51# | 16#61# =>   --  left, a
            Shown := Next_Got (Shown, -1);
            Show_Page;
         when 16#FF53# | 16#64# =>   --  right, d
            Shown := Next_Got (Shown, 1);
            Show_Page;
         when 16#FF1B# | 16#FFC1# =>   --  Escape, F4
            Toggle_Album;
         when others =>
            return False;
      end case;
      return True;
   end Album_Key;

end Postcards;
