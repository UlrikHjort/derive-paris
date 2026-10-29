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

   Shape, Spark : Meshes.Mesh;
   Built : Boolean := False;

   procedure Set (K : Decal_Kind; X, Z : Float) is
   begin
      Spots (K) := (True, X, Z);
   end Set;

   function Standing_On (X, Z : Float; K : out Decal_Kind) return Boolean is
   begin
      K := Decal_A;
      for I in Spots'Range loop
         if Spots (I).On and then (Spots (I).X - X) ** 2 + (Spots (I).Z - Z) ** 2 < 1.5 ** 2 then   --  (generous: it is hard enough to find)
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

   Clock : Float := 0.0;

   procedure Draw (Model, Extra : GL.GLint; Eye_X, Eye_Z : Float) is
   begin
      Clock := Clock + 1.0 / 60.0;
      if not Built then
         --  two strokes, a little uneven
         Meshes.Start;
         for Stroke in 0 .. 1 loop
            declare
               A  : constant Float := Ada.Numerics.Pi / 4.0 + Ada.Numerics.Pi / 2.0 * Float (Stroke)
                                      + 0.08 * Float (Stroke);
               D  : constant Vec3 := (Cos (A), 0.0, Sin (A));
               W  : constant Vec3 := (-Sin (A), 0.0, Cos (A));
               L  : constant Float := 0.62 - 0.06 * Float (Stroke);   --  a big cross, a metre and more
               T  : constant Float := 0.08;
            begin
               Meshes.Quad ((-L) * D - T * W, L * D - 0.7 * T * W, L * D + 0.7 * T * W, (-L) * D + T * W,
                            Mat_Decal);
            end;
         end loop;
         Meshes.Finish (Shape);
         --  a spark: a tiny glowing speck (a lamp, in uExtraColor)
         Meshes.Start;
         Meshes.Box (-0.04, 0.04, -0.04, 0.04, -0.04, 0.04, 50.0);
         Meshes.Finish (Spark);
         Built := True;
      end if;
      for S of Spots loop
         if S.On then
            declare
               D    : constant Float := Sqrt ((S.X - Eye_X) ** 2 + (S.Z - Eye_Z) ** 2);
               --  seen from 30 m on foot, clearer as you come, and now
               --  and then it seems to catch the light
               Glint : constant Float := 0.15 * Float'Max (0.0, Sin (Clock * 1.3 + S.X));
               Fade : constant Float := (0.8 + Glint) * Float'Max (0.0, Float'Min (1.0, (30.0 - D) / 18.0));
            begin
               if Fade > 0.0 then
                  Shaders.Set (Extra, Vec3'(Fade, 0.0, 0.0));
                  Shaders.Set (Model, Translation ((S.X, Terrain.Height (S.X, S.Z) + 0.04, S.Z)));
                  Meshes.Draw (Shape);
               end if;
               --  a few blue sparks drifting over it, seen from further
               --  (out to 45 m), to make you look closer
               if D < 45.0 then
                  Shaders.Set (Extra, Vec3'(0.25, 0.5, 1.0));
                  for K in 0 .. 4 loop
                     declare
                        Ph : constant Float := Clock * (0.35 + 0.07 * Float (K)) + Float (K) * 1.7 + S.Z;
                        Up : constant Float := 0.25 + 1.1 * (Ph / 2.0 - Float'Floor (Ph / 2.0));   --  rising, again and again
                        R  : constant Float := 0.35 + 0.1 * Float (K mod 3);
                     begin
                        Shaders.Set (Model, Translation ((S.X + R * Cos (Ph * 2.0), Terrain.Height (S.X, S.Z) + Up,
                                                          S.Z + R * Sin (Ph * 2.0))));
                        Meshes.Draw (Spark);
                     end;
                  end loop;
               end if;
            end;
         end if;
      end loop;
   end Draw;

end Decals;
