--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with Ada.Unchecked_Deallocation;

with Geo;
with Notes;

package body Terrain is


   Bank_Level : constant := 34.0;   --  metres above sea level: the new zero
   Fill_Below : constant := 29.8;   --  the river and the lower quays

   type Grid is array (Natural range <>) of Float;
   type Grid_Access is access Grid;
   procedure Free is new Ada.Unchecked_Deallocation (Grid, Grid_Access);

   H     : Grid_Access;
   W, Ht : Natural := 0;
   South, West, North, East : Long_Float := 0.0;

   function Loaded return Boolean is (H /= null);

   function At_Cell (I, J : Natural) return Float is (H (J * W + I));

   procedure Fill_River is
      Low  : array (0 .. W * Ht - 1) of Boolean;
      Next : Grid_Access := new Grid (0 .. W * Ht - 1);
      Left : Natural;
   begin
      for K in Low'Range loop
         Low (K) := H (K) < Fill_Below;
      end loop;
      --  grow the banks into the channel, a ring of cells at a time
      for Round in 1 .. 200 loop
         Next.all := H.all;
         Left := 0;
         for J in 0 .. Ht - 1 loop
            for I in 0 .. W - 1 loop
               if Low (J * W + I) then
                  declare
                     Sum : Float := 0.0;
                     N   : Natural := 0;
                     procedure Take (II, JJ : Integer) is
                     begin
                        if II in 0 .. W - 1 and then JJ in 0 .. Ht - 1
                          and then not Low (JJ * W + II)
                        then
                           Sum := Sum + H (JJ * W + II);
                           N := N + 1;
                        end if;
                     end Take;
                  begin
                     Take (I - 1, J);
                     Take (I + 1, J);
                     Take (I, J - 1);
                     Take (I, J + 1);
                     if N > 0 then
                        Next (J * W + I) := Sum / Float (N);
                     else
                        Left := Left + 1;
                     end if;
                  end;
               end if;
            end loop;
         end loop;
         for K in Low'Range loop
            if Low (K) and then Next (K) /= H (K) then
               Low (K) := False;
            end if;
         end loop;
         H.all := Next.all;
         exit when Left = 0;
      end loop;
      Free (Next);
   end Fill_River;

   --  Two passes of a 5 x 5 box blur (about 25 m)
   procedure Smooth is
      Tmp : Grid_Access := new Grid (0 .. W * Ht - 1);
      R   : constant := 2;
   begin
      for Pass in 1 .. 2 loop
         for J in 0 .. Ht - 1 loop
            for I in 0 .. W - 1 loop
               declare
                  Sum : Float := 0.0;
                  N   : Natural := 0;
               begin
                  for II in Integer'Max (0, I - R) .. Integer'Min (W - 1, I + R) loop
                     Sum := Sum + H (J * W + II);
                     N := N + 1;
                  end loop;
                  Tmp (J * W + I) := Sum / Float (N);
               end;
            end loop;
         end loop;
         for J in 0 .. Ht - 1 loop
            for I in 0 .. W - 1 loop
               declare
                  Sum : Float := 0.0;
                  N   : Natural := 0;
               begin
                  for JJ in Integer'Max (0, J - R) .. Integer'Min (Ht - 1, J + R) loop
                     Sum := Sum + Tmp (JJ * W + I);
                     N := N + 1;
                  end loop;
                  H (J * W + I) := Sum / Float (N);
               end;
            end loop;
         end loop;
      end loop;
      Free (Tmp);
   end Smooth;

   procedure Load (Directory : String := "data/elevation") is
      Header : constant String := Directory & "/paris.txt";
      Data   : constant String := Directory & "/paris.bil";
   begin
      if H /= null or else not Ada.Directories.Exists (Header)
        or else not Ada.Directories.Exists (Data)
      then
         return;
      end if;
      --  "south west north east width height"
      declare
         F : Ada.Text_IO.File_Type;
         package LF_IO is new Ada.Text_IO.Float_IO (Long_Float);
         package N_IO is new Ada.Text_IO.Integer_IO (Natural);
      begin
         Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Header);
         LF_IO.Get (F, South);
         LF_IO.Get (F, West);
         LF_IO.Get (F, North);
         LF_IO.Get (F, East);
         N_IO.Get (F, W);
         N_IO.Get (F, Ht);
         Ada.Text_IO.Close (F);
      end;
      if Natural (Ada.Directories.Size (Data)) /= W * Ht * 4 then
         Ada.Text_IO.Put_Line ("Terrain: " & Data & " has the wrong size, the ground stays flat");
         return;
      end if;
      H := new Grid (0 .. W * Ht - 1);
      declare
         use Ada.Streams.Stream_IO;
         F : File_Type;
      begin
         Open (F, In_File, Data);
         Grid'Read (Stream (F), H.all);
         Close (F);
      end;
      Fill_River;
      Smooth;
      for V of H.all loop
         V := V - Bank_Level;
      end loop;
      Notes.Say ("Terrain:" & W'Image & " x" & Ht'Image & " heights");
   exception
      when others =>
         Ada.Text_IO.Put_Line ("Terrain: could not read " & Data & ", the ground stays flat");
         if H /= null then
            Free (H);
         end if;
   end Load;

   function Height (X, Z : Long_Float) return Long_Float is
      Lat, Lon : Long_Float;
   begin
      if H = null then
         return 0.0;
      end if;
      Geo.To_Lat_Lon (X, Z, Lat, Lon);
      declare
         --  pixel centres: column 0 at West + half a cell, row 0 at North
         FX : constant Long_Float :=
           Long_Float'Max (0.0, Long_Float'Min (Long_Float (W - 1),
                           (Lon - West) / (East - West) * Long_Float (W) - 0.5));
         FY : constant Long_Float :=
           Long_Float'Max (0.0, Long_Float'Min (Long_Float (Ht - 1),
                           (North - Lat) / (North - South) * Long_Float (Ht) - 0.5));
         I  : constant Natural := Natural'Min (W - 2, Natural (Long_Float'Floor (FX)));
         J  : constant Natural := Natural'Min (Ht - 2, Natural (Long_Float'Floor (FY)));
         TX : constant Long_Float := FX - Long_Float (I);
         TY : constant Long_Float := FY - Long_Float (J);
         A  : constant Long_Float := Long_Float (At_Cell (I, J));
         B  : constant Long_Float := Long_Float (At_Cell (I + 1, J));
         C  : constant Long_Float := Long_Float (At_Cell (I, J + 1));
         D  : constant Long_Float := Long_Float (At_Cell (I + 1, J + 1));
      begin
         return (A * (1.0 - TX) + B * TX) * (1.0 - TY) + (C * (1.0 - TX) + D * TX) * TY;
      end;
   end Height;

   function Height (X, Z : Float) return Float is
     (Float (Height (Long_Float (X), Long_Float (Z))));

   procedure Slope (X, Z : Float; DX, DZ : out Float) is
      E : constant := 2.0;
   begin
      DX := (Height (X + E, Z) - Height (X - E, Z)) / (2.0 * E);
      DZ := (Height (X, Z + E) - Height (X, Z - E)) / (2.0 * E);
   end Slope;

   procedure Bounds (X0, Z0, X1, Z1 : out Float) is
      A, B, C, D : Long_Float;
   begin
      if H = null then
         X0 := 0.0; Z0 := 0.0; X1 := 0.0; Z1 := 0.0;
         return;
      end if;
      Geo.To_Local (North, West, A, B);
      Geo.To_Local (South, East, C, D);
      X0 := Float (A); Z0 := Float (B); X1 := Float (C); Z1 := Float (D);
   end Bounds;

end Terrain;
