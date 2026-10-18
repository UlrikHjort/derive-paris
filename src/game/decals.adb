--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;

with Math3D;
with Meshes;
with Shaders;
with Terrain;

package body Decals is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;

   Mat_Decal : constant := 59.0;

   type Spot is record
      On   : Boolean := False;
      X, Z : Float := 0.0;
   end record;
   Spots : array (Decal_Kind) of Spot;

   Shape : Meshes.Mesh;
   Built : Boolean := False;

   procedure Set (K : Decal_Kind; X, Z : Float) is
   begin
      Spots (K) := (True, X, Z);
   end Set;

   function Standing_On (X, Z : Float; K : out Decal_Kind) return Boolean is
   begin
      K := Decal_A;
      for I in Spots'Range loop
         if Spots (I).On and then (Spots (I).X - X) ** 2 + (Spots (I).Z - Z) ** 2 < 0.7 ** 2 then
            K := I;
            return True;
         end if;
      end loop;
      return False;
   end Standing_On;

   procedure Position (K : Decal_Kind; X, Z : out Float) is
   begin
      X := Spots (K).X;
      Z := Spots (K).Z;
   end Position;

   procedure Draw (Model, Extra : GL.GLint; Eye_X, Eye_Z : Float) is
   begin
      if not Built then
         --  two strokes, a little uneven
         Meshes.Start;
         for Stroke in 0 .. 1 loop
            declare
               A  : constant Float := Ada.Numerics.Pi / 4.0 + Ada.Numerics.Pi / 2.0 * Float (Stroke)
                                      + 0.08 * Float (Stroke);
               D  : constant Vec3 := (Cos (A), 0.0, Sin (A));
               W  : constant Vec3 := (-Sin (A), 0.0, Cos (A));
               L  : constant Float := 0.36 - 0.04 * Float (Stroke);
               T  : constant Float := 0.05;
            begin
               Meshes.Quad ((-L) * D - T * W, L * D - 0.7 * T * W, L * D + 0.7 * T * W, (-L) * D + T * W,
                            Mat_Decal);
            end;
         end loop;
         Meshes.Finish (Shape);
         Built := True;
      end if;
      for S of Spots loop
         if S.On then
            declare
               D    : constant Float := Sqrt ((S.X - Eye_X) ** 2 + (S.Z - Eye_Z) ** 2);
               Fade : constant Float := 0.62 * Float'Max (0.0, Float'Min (1.0, (12.0 - D) / 7.0));
            begin
               if Fade > 0.0 then
                  Shaders.Set (Extra, Vec3'(Fade, 0.0, 0.0));
                  Shaders.Set (Model, Translation ((S.X, Terrain.Height (S.X, S.Z) + 0.04, S.Z)));
                  Meshes.Draw (Shape);
               end if;
            end;
         end if;
      end loop;
   end Draw;

end Decals;
