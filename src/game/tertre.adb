--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;

with Figures;
with Geo;
with Meshes;
with Shaders;
with Terrain;

package body Tertre is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;

   Pi : constant := Ada.Numerics.Pi;

   --  the middle of the Place du Tertre, and the vineyard's outline (from
   --  OpenStreetMap)
   Square_Lat : constant := 48.886507;
   Square_Lon : constant := 2.340730;
   Vine_Lat : constant array (1 .. 9) of Long_Float :=
     (48.888108, 48.888036, 48.888093, 48.888443, 48.888455, 48.888430, 48.888254, 48.888199, 48.888186);
   Vine_Lon : constant array (1 .. 9) of Long_Float :=
     (2.339829, 2.340484, 2.340497, 2.340580, 2.339939, 2.339884, 2.339839, 2.339835, 2.339834);

   Easels : constant := 14;
   Placed : Boolean := False;
   Square : Vec3;
   Vine_Mid : Vec3;

   Easel_M, Stool_M, Parasol_M, Vines_M : Meshes.Mesh;
   Canvas_M : array (1 .. Easels) of Meshes.Mesh;
   Built : Boolean := False;

   type Poly is array (1 .. 9) of Vec3;
   Vine_Poly : Poly;

   procedure Place is
      X, Z : Long_Float;
   begin
      if Placed then
         return;
      end if;
      Geo.To_Local (Square_Lat, Square_Lon, X, Z);
      Square := (Float (X), Terrain.Height (Float (X), Float (Z)), Float (Z));
      Vine_Mid := (0.0, 0.0, 0.0);
      for I in Vine_Poly'Range loop
         Geo.To_Local (Vine_Lat (I), Vine_Lon (I), X, Z);
         Vine_Poly (I) := (Float (X), 0.0, Float (Z));
         Vine_Mid := Vine_Mid + Vine_Poly (I);
      end loop;
      Vine_Mid := (1.0 / 9.0) * Vine_Mid;
      Placed := True;
   end Place;

   function Inside (X, Z : Float) return Boolean is
      Is_In : Boolean := False;
      J : Positive := Vine_Poly'Last;
   begin
      for I in Vine_Poly'Range loop
         declare
            A : constant Vec3 := Vine_Poly (I);
            B : constant Vec3 := Vine_Poly (J);
         begin
            if (A.Z > Z) /= (B.Z > Z)
              and then X < (B.X - A.X) * (Z - A.Z) / (B.Z - A.Z) + A.X
            then
               Is_In := not Is_In;
            end if;
         end;
         J := I;
      end loop;
      return Is_In;
   end Inside;

   --  The easel's place round the square: on a ring between the trees
   function Spot (K : Positive; Face : out Float) return Vec3 is
      A : constant Float := 2.0 * Pi * (Float (K) + 0.3 * Sin (Float (K) * 2.1)) / Float (Easels);
      R : constant Float := 11.0 + 4.0 * Sin (Float (K) * 1.7);
      P : constant Vec3 := Square + Vec3'(R * Cos (A), 0.0, R * Sin (A));
   begin
      Face := A + Pi / 2.0 + 0.4 * Sin (Float (K));   --  the canvas faces round the square
      return (P.X, Terrain.Height (P.X, P.Z), P.Z);
   end Spot;

   procedure Build is
      use Meshes;
   begin
      --  an easel: three legs, the ledge (front -Z: the painter stands at +Z)
      Start;
      Box (-0.35, -0.3, 0.0, 1.75, -0.05, 0.05, 60.0);
      Box (0.3, 0.35, 0.0, 1.75, -0.05, 0.05, 60.0);
      Box (-0.03, 0.03, 0.0, 1.7, 0.35, 0.45, 60.0);
      Box (-0.4, 0.4, 0.85, 0.9, -0.08, 0.06, 60.0);
      Finish (Easel_M);
      --  the canvases, each its own painting (the gallery's styles)
      for K in Canvas_M'Range loop
         Start;
         Quad_UV ((0.36, 0.9, -0.07), (-0.36, 0.9, -0.07), (-0.36, 1.6, -0.07), (0.36, 1.6, -0.07),
                  (0.0, 0.0, -1.0), 51.0, Float ((K * 37) mod 16 + 16 * (K mod 8) + 128 * K));
         Quad_UV ((-0.36, 0.9, -0.06), (0.36, 0.9, -0.06), (0.36, 1.6, -0.06), (-0.36, 1.6, -0.06),
                  (0.0, 0.0, 1.0), 51.0, Float ((K * 37) mod 16 + 16 * (K mod 8) + 128 * K));
         Finish (Canvas_M (K));
      end loop;
      --  a folding stool
      Start;
      Box (-0.2, 0.2, 0.42, 0.47, -0.2, 0.2, 17.0);
      Box (-0.18, -0.14, 0.0, 0.42, -0.18, 0.18, 26.0);
      Box (0.14, 0.18, 0.0, 0.42, -0.18, 0.18, 26.0);
      Finish (Stool_M);
      --  a parasol, striped
      Start;
      Box (-0.03, 0.03, 0.0, 2.2, -0.03, 0.03, 26.0);
      for K in 0 .. 7 loop
         declare
            A0 : constant Float := 2.0 * Pi * Float (K) / 8.0;
            A1 : constant Float := 2.0 * Pi * Float (K + 1) / 8.0;
            T  : constant Vec3 := (0.0, 2.45, 0.0);
            P0 : constant Vec3 := (1.1 * Cos (A0), 2.05, 1.1 * Sin (A0));
            P1 : constant Vec3 := (1.1 * Cos (A1), 2.05, 1.1 * Sin (A1));
         begin
            Quad_UV (P0, P1, T, T, (0.0, 1.0, 0.0), 65.0, Float (K mod 2) + 2.0, 1.0, 1.0);
            Quad_UV (P1, P0, T, T, (0.0, -1.0, 0.0), 65.0, Float (K mod 2) + 2.0, 1.0, 1.0);
         end;
      end loop;
      Finish (Parasol_M);
      --  the vines: rows across the slope, a post every 1.2 m and the
      --  leaves along the wire
      Start;
      declare
         X0, X1, Z0, Z1 : Float := 0.0;
      begin
         X0 := Vine_Poly (1).X;
         X1 := X0;
         Z0 := Vine_Poly (1).Z;
         Z1 := Z0;
         for P of Vine_Poly loop
            X0 := Float'Min (X0, P.X);
            X1 := Float'Max (X1, P.X);
            Z0 := Float'Min (Z0, P.Z);
            Z1 := Float'Max (Z1, P.Z);
         end loop;
         declare
            Z : Float := Z0 + 0.9;
         begin
            while Z < Z1 loop
               declare
                  X : Float := X0 + 0.6;
               begin
                  while X < X1 loop
                     if Inside (X, Z) and then Inside (X + 1.2, Z) then
                        declare
                           G  : constant Float := Terrain.Height (X, Z);
                           G2 : constant Float := Terrain.Height (X + 1.2, Z);
                        begin
                           Box (X - 0.03, X + 0.03, G, G + 1.2, Z - 0.03, Z + 0.03, 60.0);
                           --  the leaves, following the slope
                           --  (a seed for the leaves' shade, as a tree's)
                           Quad_UV ((X, G + 0.45, Z - 0.28), (X + 1.2, G2 + 0.45, Z - 0.28),
                                    (X + 1.2, G2 + 1.15, Z - 0.22), (X, G + 1.15, Z - 0.22),
                                    (0.0, 0.3, -1.0), 14.0, 0.75);
                           Quad_UV ((X + 1.2, G2 + 0.45, Z + 0.28), (X, G + 0.45, Z + 0.28),
                                    (X, G + 1.15, Z + 0.22), (X + 1.2, G2 + 1.15, Z + 0.22),
                                    (0.0, 0.3, 1.0), 14.0, 0.75);
                           Quad_UV ((X, G + 1.15, Z - 0.22), (X + 1.2, G2 + 1.15, Z - 0.22),
                                    (X + 1.2, G2 + 1.15, Z + 0.22), (X, G + 1.15, Z + 0.22),
                                    (0.0, 1.0, 0.0), 14.0, 0.75);
                        end;
                     end if;
                     X := X + 1.2;
                  end loop;
               end;
               Z := Z + 1.8;
            end loop;
         end;
      end;
      Finish (Vines_M);
      Built := True;
   end Build;

   procedure Draw (Model, Paint, Skin, Legs : GL.GLint; Cam : Vec3; Hour, Rain, Time : Float) is
   begin
      Place;
      if (Cam.X - Square.X) ** 2 + (Cam.Z - Square.Z) ** 2 > 500.0 ** 2 then
         return;
      end if;
      if not Built then
         Build;
      end if;
      Shaders.Set (Model, Identity);
      Meshes.Draw (Vines_M);
      --  the painters: by day, and not in the rain
      if Hour < 9.5 or else Hour > 19.5 or else Rain > 0.4 then
         return;
      end if;
      Figures.Set_Locations ((Model, Paint, Skin, Legs));
      for K in 1 .. Easels loop
         declare
            Face : Float;
            P : constant Vec3 := Spot (K, Face);
            M : constant Mat4 := Translation (P) * Rotation_Y (-Face);
         begin
            Shaders.Set (Model, M);
            Meshes.Draw (Easel_M);
            Meshes.Draw (Canvas_M (K));
            Shaders.Set (Model, M * Translation ((0.0, 0.0, 1.2)));
            Meshes.Draw (Stool_M);
            if K mod 3 = 0 then
               Shaders.Set (Model, M * Translation ((0.8, 0.0, 1.0)));
               Meshes.Draw (Parasol_M);
            end if;
            --  the painter, before the canvas, the brush moving
            Figures.Person (M * Translation ((0.15, 0.0, 0.75)) * Rotation_Y (Pi),
                            (case K mod 5 is
                                when 0 => (0.15, 0.15, 0.2), when 1 => (0.55, 0.15, 0.15),
                                when 2 => (0.85, 0.8, 0.7), when 3 => (0.2, 0.3, 0.45),
                                when others => (0.35, 0.4, 0.25)),
                            (case K mod 4 is
                                when 0 => (0.86, 0.68, 0.56), when 1 => (0.76, 0.57, 0.44),
                                when 2 => (0.58, 0.40, 0.29), when others => (0.40, 0.27, 0.19)),
                            (0.15, 0.15, 0.18),
                            Hat => (if K mod 2 = 0 then Figures.Cap else Figures.None),
                            Hat_Colour => (0.1, 0.1, 0.12),
                            Arm_Up => -0.9 + 0.25 * Sin (Time * 2.3 + Float (K)));
            --  now and then someone watching
            if K mod 2 = 1 then
               Figures.Person (M * Translation ((-1.0, 0.0, 1.6)) * Rotation_Y (Pi + 0.5),
                               (0.6, 0.55, 0.45), (0.86, 0.68, 0.56), (0.3, 0.3, 0.35));
            end if;
         end;
      end loop;
      Shaders.Set (Model, Identity);
   end Draw;

end Tertre;
