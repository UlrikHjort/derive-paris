--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Numerics.Float_Random;
with Ada.Text_IO;

with Almanac;
with Figures;
with Geo;
with Meshes;
with Shaders;
with Terrain;

package body Garden_Chairs is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;

   Pi : constant := Ada.Numerics.Pi;

   Green : constant Vec3 := (0.27, 0.40, 0.31);   --  the faded sage of the gardens
   Near  : constant := 700.0;   --  from a garden's middle: drawn
   Seen  : constant := 110.0;   --  people, this far off

   type Chair is record
      P     : Vec3 := (0.0, 0.0, 0.0);
      Angle : Float := 0.0;
      Low   : Boolean := False;
      Hash  : Float := 0.0;     --  who sits here, and when
   end record;

   Max_Chairs : constant := 1200;
   Chairs : array (1 .. Max_Chairs) of Chair;
   Count  : Natural := 0;

   type Park_Kind is (Luxembourg, Tuileries);
   type Park is record
      Mid   : Vec3 := (0.0, 0.0, 0.0);
      First : Positive := 1;
      Last  : Natural := 0;
      Mesh  : Meshes.Mesh;
   end record;
   Parks : array (Park_Kind) of Park;

   Gen : Ada.Numerics.Float_Random.Generator;
   Loaded, Built : Boolean := False;

   function Rnd return Float is (Ada.Numerics.Float_Random.Random (Gen));

   procedure Load is
      use Ada.Text_IO;
      F : File_Type;
      Totals : array (Park_Kind) of Natural := (others => 0);
   begin
      Loaded := True;
      Ada.Numerics.Float_Random.Reset (Gen);
      Open (F, In_File, "data/chairs.txt");
      while not End_Of_File (F) loop
         declare
            L : constant String := Get_Line (F);
            V : array (1 .. 3) of Long_Float := (others => 0.0);
            First : Positive := L'First + 2;
            K : Natural := 0;
         begin
            if L'Length > 2 and then L (L'First) /= '#' and then Count < Max_Chairs then
               for I in First .. L'Last + 1 loop
                  if I > L'Last or else L (I) = ' ' then
                     if I > First and then K < 3 then
                        K := K + 1;
                        V (K) := Long_Float'Value (L (First .. I - 1));
                     end if;
                     First := I + 1;
                  end if;
               end loop;
               --  people have moved them since; now and then one has gone
               if K = 3 and then Rnd > 0.08 then
                  declare
                     X, Z : Long_Float;
                     Which : constant Park_Kind := (if L (L'First) = 'L' then Luxembourg else Tuileries);
                     PX, PZ : Float;
                  begin
                     Geo.To_Local (V (1), V (2), X, Z);
                     PX := Float (X) + 0.5 * (Rnd - 0.5);
                     PZ := Float (Z) + 0.5 * (Rnd - 0.5);
                     Count := Count + 1;
                     Chairs (Count) :=
                       (P     => (PX, Terrain.Height (PX, PZ), PZ),
                        Angle => -Float (V (3)) * Pi / 180.0 + 0.5 * (Rnd - 0.5),
                        Low   => Rnd < 0.35,
                        Hash  => Rnd);
                     if Totals (Which) = 0 then
                        Parks (Which).First := Count;
                     end if;
                     Totals (Which) := Totals (Which) + 1;
                     Parks (Which).Last := Count;
                     Parks (Which).Mid := Parks (Which).Mid + Chairs (Count).P;
                  end;
               end if;
            end if;
         end;
      end loop;
      Close (F);
      for K in Parks'Range loop
         if Totals (K) > 0 then
            Parks (K).Mid := (1.0 / Float (Totals (K))) * Parks (K).Mid;
         end if;
      end loop;
   exception
      when Name_Error => null;   --  no chairs then
   end Load;

   --  A slab of a chair, in the chair's own coordinates (front -Z), tipped
   --  back by Tip about (Y, Z) = (PY, PZ), and put in the world
   procedure Slab (C : Chair; X0, X1, Y0, Y1, Z0, Z1 : Float;
                   Tip : Float := 0.0; PY, PZ : Float := 0.0) is
      CA : constant Float := Cos (C.Angle);
      SA : constant Float := Sin (C.Angle);
      CT : constant Float := Cos (Tip);
      ST : constant Float := Sin (Tip);
      function W (X, Y, Z : Float) return Vec3 is
         DY : constant Float := Y - PY;
         DZ : constant Float := Z - PZ;
         TY : constant Float := PY + DY * CT - DZ * ST;
         TZ : constant Float := PZ + DY * ST + DZ * CT;
      begin
         return C.P + Vec3'(X * CA + TZ * SA, TY, -X * SA + TZ * CA);
      end W;
      Mat : constant Float := Meshes.Mat_Cloth;
   begin
      Meshes.Quad (W (X0, Y1, Z1), W (X1, Y1, Z1), W (X1, Y1, Z0), W (X0, Y1, Z0), Mat);
      Meshes.Quad (W (X0, Y0, Z0), W (X1, Y0, Z0), W (X1, Y0, Z1), W (X0, Y0, Z1), Mat);
      Meshes.Quad (W (X0, Y0, Z1), W (X1, Y0, Z1), W (X1, Y1, Z1), W (X0, Y1, Z1), Mat);
      Meshes.Quad (W (X1, Y0, Z0), W (X0, Y0, Z0), W (X0, Y1, Z0), W (X1, Y1, Z0), Mat);
      Meshes.Quad (W (X1, Y0, Z1), W (X1, Y0, Z0), W (X1, Y1, Z0), W (X1, Y1, Z1), Mat);
      Meshes.Quad (W (X0, Y0, Z0), W (X0, Y0, Z1), W (X0, Y1, Z1), W (X0, Y1, Z0), Mat);
   end Slab;

   Seat_Height : constant array (Boolean) of Float := (False => 0.46, True => 0.32);
   Back_Tip    : constant array (Boolean) of Float := (False => 0.2, True => 0.55);

   procedure Build_Chair (C : Chair) is
      H    : constant Float := Seat_Height (C.Low);
      Tip  : constant Float := Back_Tip (C.Low);
      Seat : constant Float := (if C.Low then 0.14 else 0.03);   --  the seat falls to the back
      Back_Z : constant Float := 0.21;
      Thin : constant := 0.016;
   begin
      --  the legs
      Slab (C, -0.2, -0.2 + 2.0 * Thin, 0.0, H + 0.1, -0.2, -0.2 + 2.0 * Thin);
      Slab (C, 0.2 - 2.0 * Thin, 0.2, 0.0, H + 0.1, -0.2, -0.2 + 2.0 * Thin);
      Slab (C, -0.2, -0.2 + 2.0 * Thin, 0.0, H, Back_Z - 2.0 * Thin, Back_Z);
      Slab (C, 0.2 - 2.0 * Thin, 0.2, 0.0, H, Back_Z - 2.0 * Thin, Back_Z);
      --  the slats of the seat
      for K in 0 .. 4 loop
         declare
            Z : constant Float := -0.23 + 0.092 * Float (K);
         begin
            Slab (C, -0.22, 0.22, H, H + Thin, Z, Z + 0.07, Tip => Seat, PY => H, PZ => 0.0);
         end;
      end loop;
      --  and of the back, tipped back from the seat
      for K in 0 .. 3 loop
         declare
            Y : constant Float := H + 0.1 + 0.11 * Float (K);
         begin
            Slab (C, -0.21, 0.21, Y, Y + 0.08, Back_Z, Back_Z + Thin, Tip => Tip, PY => H, PZ => Back_Z);
         end;
      end loop;
   end Build_Chair;

   procedure Build is
   begin
      for K in Parks'Range loop
         Meshes.Start;
         for I in Parks (K).First .. Parks (K).Last loop
            Build_Chair (Chairs (I));
         end loop;
         Meshes.Finish (Parks (K).Mesh);
      end loop;
      Built := True;
   end Build;

   --  How many sit out: the share of the chairs taken, by the season
   function Taken return Float is
     (case Almanac.Month is
         when 5 .. 9 => 0.3,
         when 4 | 10 => 0.14,
         when 3 | 11 => 0.05,
         when others => 0.02);

   procedure Draw (Model, Paint, Skin, Legs : GL.GLint; Cam : Vec3;
                   Hour, Rain : Float) is
      Near_Any : Boolean := False;
   begin
      if not Loaded then
         Load;
      end if;
      if Count = 0 then
         return;
      end if;
      for K in Parks'Range loop
         Near_Any := Near_Any
           or else (Cam.X - Parks (K).Mid.X) ** 2 + (Cam.Z - Parks (K).Mid.Z) ** 2 < Near ** 2;
      end loop;
      if not Near_Any then
         return;
      end if;
      if not Built then
         Build;
      end if;
      Shaders.Set (Model, Identity);
      Shaders.Set (Paint, Green);
      for K in Parks'Range loop
         if (Cam.X - Parks (K).Mid.X) ** 2 + (Cam.Z - Parks (K).Mid.Z) ** 2 < Near ** 2 then
            Meshes.Draw (Parks (K).Mesh);
         end if;
      end loop;
      --  people, by day and in the dry
      if Hour < 9.5 or else Hour > 19.5 or else Rain > 0.2 then
         return;
      end if;
      Figures.Set_Locations ((Model, Paint, Skin, Legs));
      for I in 1 .. Count loop
         declare
            C : Chair renames Chairs (I);
         begin
            if C.Hash < Taken
              and then (Cam.X - C.P.X) ** 2 + (Cam.Z - C.P.Z) ** 2 < Seen ** 2
            then
               declare
                  N : constant Natural := Natural (C.Hash * 9973.0 * 40.0);
               begin
                  Figures.Seated
                    (Translation (C.P) * Rotation_Y (C.Angle),
                     (case N mod 6 is
                         when 0 => (0.75, 0.2, 0.2), when 1 => (0.2, 0.3, 0.5),
                         when 2 => (0.85, 0.82, 0.72), when 3 => (0.2, 0.2, 0.22),
                         when 4 => (0.35, 0.5, 0.45), when others => (0.65, 0.55, 0.3)),
                     (case N mod 4 is
                         when 0 => (0.86, 0.68, 0.56), when 1 => (0.76, 0.57, 0.44),
                         when 2 => (0.58, 0.40, 0.29), when others => (0.40, 0.27, 0.19)),
                     (case N mod 3 is
                         when 0 => (0.15, 0.17, 0.25), when 1 => (0.5, 0.45, 0.38),
                         when others => (0.2, 0.2, 0.22)),
                     Seat_Height (C.Low) + 0.02, Back_Tip (C.Low));
               end;
            end if;
         end;
      end loop;
      Shaders.Set (Model, Identity);
   end Draw;

end Garden_Chairs;
