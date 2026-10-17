--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;

with Geo;
with Math3D;
with Meshes;

package body Xmas is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;

   Mat_Fir  : constant := 37.0;
   Mat_Star : constant := 38.0;

   type Site is record
      Lat, Lon : Long_Float;
      Height   : Float;
   end record;

   Sites : constant array (1 .. 4) of Site :=
     ((48.85335, 2.34805, 22.0),    --  parvis de Notre-Dame
      (48.85660, 2.35130, 18.0),    --  place de l'Hôtel de Ville
      (48.85112, 2.33358, 14.0),    --  place Saint-Sulpice
      (48.86215, 2.28760, 16.0));   --  Trocadéro

   Trees : Meshes.Mesh;

   --  A cone of quads, faces turned outwards
   procedure Cone (C : Vec3; Radius, Base_Y, Top_Y : Float; Mat : Float) is
      Segs : constant := 18;
      Apex : constant Vec3 := (C.X, Top_Y, C.Z);
   begin
      for I in 0 .. Segs - 1 loop
         declare
            A0 : constant Float := 2.0 * Ada.Numerics.Pi * Float (I) / Float (Segs);
            A1 : constant Float := 2.0 * Ada.Numerics.Pi * Float (I + 1) / Float (Segs);
            P0 : constant Vec3 := (C.X + Radius * Cos (A0), Base_Y, C.Z + Radius * Sin (A0));
            P1 : constant Vec3 := (C.X + Radius * Cos (A1), Base_Y, C.Z + Radius * Sin (A1));
            N  : constant Vec3 := Cross (Apex - P0, P1 - P0);
         begin
            if Dot (N, P0 - Vec3'(C.X, Base_Y, C.Z)) >= 0.0 then
               Meshes.Quad (P0, Apex, Apex, P1, Mat);
            else
               Meshes.Quad (P1, Apex, Apex, P0, Mat);
            end if;
            --  underside
            Meshes.Quad (P0, P1, (C.X, Base_Y, C.Z), (C.X, Base_Y, C.Z), Mat);
         end;
      end loop;
   end Cone;

   procedure Create is
   begin
      Meshes.Start;
      for S of Sites loop
         declare
            X, Z : Long_Float;
            H    : constant Float := S.Height;
         begin
            Geo.To_Local (S.Lat, S.Lon, X, Z);
            declare
               C : constant Vec3 := (Float (X), 0.0, Float (Z));
            begin
               --  trunk in a big red tub
               Meshes.Box (C.X - 1.6, C.X + 1.6, 0.0, 1.2, C.Z - 1.6, C.Z + 1.6, 19.0);
               Meshes.Box (C.X - 0.4, C.X + 0.4, 1.2, 0.2 * H, C.Z - 0.4, C.Z + 0.4, 13.0);
               --  four tiers of branches
               for T in 0 .. 3 loop
                  Cone (C, 0.33 * H * (1.0 - 0.21 * Float (T)),
                        0.1 * H + 0.2 * H * Float (T),
                        0.1 * H + 0.2 * H * Float (T) + 0.38 * H, Mat_Fir);
               end loop;
               --  the star
               declare
                  Y : constant Float := 0.1 * H + 0.6 * H + 0.38 * H;
                  R : constant Float := 0.06 * H;
               begin
                  Meshes.Box (C.X - R, C.X + R, Y - R, Y + R, C.Z - 0.15, C.Z + 0.15, Mat_Star);
                  Meshes.Box (C.X - 0.15, C.X + 0.15, Y - R, Y + R, C.Z - R, C.Z + R, Mat_Star);
               end;
            end;
         end;
      end loop;
      Meshes.Finish (Trees);
   end Create;

   procedure Draw is
   begin
      Meshes.Draw (Trees);
   end Draw;

end Xmas;
