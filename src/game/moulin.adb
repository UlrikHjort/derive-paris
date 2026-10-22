--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;

with Geo;
with Meshes;
with Road_Network;
with Shaders;
with Terrain;
with World;

package body Moulin is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;

   Pi : constant := Ada.Numerics.Pi;

   type Float_List is array (Positive range <>) of Float;

   Mat_Paint : constant := 54.0;    --  glossy, in uCarColor
   Mat_Lit   : constant := 41.0;    --  glows at night (warm)
   Mat_Wood  : constant := 13.0;

   Spot  : Vec3 := (0.0, 0.0, 0.0);   --  the foot of the mill, on the roof
   Front : Vec3 := (0.0, 0.0, -1.0);  --  towards the boulevard
   Clock : Float := 0.0;
   Tower_M, Sails_M, Lights_M : Meshes.Mesh;
   Built : Boolean := False;

   function Door return Vec3 is (Spot - Vec3'(0.0, Spot.Y, 0.0) + 8.0 * Front);

   procedure Face (A, B, C, D, N : Vec3; Mat : Float) is
   begin
      if Dot (Cross (B - A, D - A), N) >= 0.0 then
         Meshes.Quad (A, B, C, D, Mat);
      else
         Meshes.Quad (D, C, B, A, Mat);
      end if;
   end Face;

   procedure Build is
      X, Z : Long_Float;
      Roof : Float := -1.0E9;
      G    : Float;
      procedure Visit (AX, AZ, BX, BZ, Bottom, Top : Float) is
         pragma Unreferenced (AX, AZ, BX, BZ, Bottom);
      begin
         Roof := Float'Max (Roof, Top);
      end Visit;
      procedure Walls is new World.For_Walls_Near (Visit);
   begin
      Geo.To_Local (48.884110, 2.332270, X, Z);
      Spot := (Float (X), 0.0, Float (Z));
      G := Terrain.Height (Spot.X, Spot.Z);
      Walls (Spot.X, Spot.Z, 6.0);
      if Roof < -1.0E8 then
         return;   --  the tiles are not there yet
      end if;
      Spot.Y := Float'Max (G + 6.0, Roof);
      --  which way is the boulevard
      declare
         Found : Boolean;
         RX, RZ, RH : Float;
      begin
         Road_Network.Nearest_Road (Spot.X, Spot.Z, Found, RX, RZ, RH);
         if Found and then abs (RX - Spot.X) + abs (RZ - Spot.Z) > 1.0 then
            Front := Normalize (Vec3'(RX - Spot.X, 0.0, RZ - Spot.Z));
         end if;
      end;
      --  the tower: eight-sided, tapering, red, with a cap
      Meshes.Start;
      for K in 0 .. 7 loop
         declare
            A0 : constant Float := 2.0 * Pi * Float (K) / 8.0;
            A1 : constant Float := 2.0 * Pi * Float (K + 1) / 8.0;
            function P (A, R, Y : Float) return Vec3 is (Spot + Vec3'(R * Cos (A), Y, R * Sin (A)));
         begin
            Face (P (A0, 2.6, 0.0), P (A1, 2.6, 0.0), P (A1, 1.9, 8.0), P (A0, 1.9, 8.0),
                  (Cos (0.5 * (A0 + A1)), 0.2, Sin (0.5 * (A0 + A1))), Mat_Paint);
            Face (P (A0, 2.2, 8.0), P (A1, 2.2, 8.0), P (A1, 0.2, 10.5), P (A0, 0.2, 10.5),
                  (Cos (0.5 * (A0 + A1)), 0.8, Sin (0.5 * (A0 + A1))), Mat_Paint);
         end;
      end loop;
      Meshes.Finish (Tower_M);
      --  four sails on a hub, in the plane facing the boulevard, built
      --  about the hub at the origin (turned and placed in Draw)
      Meshes.Start;
      declare
         Side : constant Vec3 := (-Front.Z, 0.0, Front.X);
         Up   : constant Vec3 := (0.0, 1.0, 0.0);
      begin
         for K in 0 .. 3 loop
            declare
               A  : constant Float := Pi / 2.0 * Float (K) + Pi / 4.0;
               D  : constant Vec3 := Cos (A) * Side + Sin (A) * Up;
               N  : constant Vec3 := Cross (D, Front);
            begin
               --  the arm, and a lattice blade along it
               Face (0.6 * D - 0.06 * N, 6.5 * D - 0.06 * N, 6.5 * D + 0.06 * N, 0.6 * D + 0.06 * N, Front, Mat_Wood);
               Face (1.5 * D, 6.4 * D, 6.4 * D + 1.3 * N, 1.5 * D + 1.3 * N, Front, Mat_Wood);
               Face (1.5 * D, 6.4 * D, 6.4 * D + 1.3 * N, 1.5 * D + 1.3 * N, (-1.0) * Front, Mat_Wood);
            end;
         end loop;
      end;
      Meshes.Finish (Sails_M);
      --  the lights along the sails
      Meshes.Start;
      declare
         Side : constant Vec3 := (-Front.Z, 0.0, Front.X);
         Up   : constant Vec3 := (0.0, 1.0, 0.0);
      begin
         for K in 0 .. 3 loop
            declare
               A : constant Float := Pi / 2.0 * Float (K) + Pi / 4.0;
               D : constant Vec3 := Cos (A) * Side + Sin (A) * Up;
               N : constant Vec3 := Cross (D, Front);
            begin
               for L in 0 .. 10 loop
                  for Edge of Float_List'(0.0, 1.3) loop
                     declare
                        P : constant Vec3 := (1.5 + 0.49 * Float (L)) * D + Edge * N + 0.08 * Front;
                     begin
                        Meshes.Box (P.X - 0.07, P.X + 0.07, P.Y - 0.07, P.Y + 0.07, P.Z - 0.07, P.Z + 0.07, Mat_Lit);
                     end;
                  end loop;
               end loop;
            end;
         end loop;
      end;
      Meshes.Finish (Lights_M);
      Built := True;
   end Build;

   procedure Update (Dt : Float) is
   begin
      Clock := Clock + Dt;
   end Update;

   procedure Draw (Model, Paint : GL.GLint; Cam : Vec3) is
      X, Z : Long_Float;
   begin
      Geo.To_Local (48.884110, 2.332270, X, Z);
      if (Cam.X - Float (X)) ** 2 + (Cam.Z - Float (Z)) ** 2 > 900.0 ** 2 then
         return;
      end if;
      if not Built then
         Build;
         if not Built then
            return;
         end if;
      end if;
      Shaders.Set (Paint, Vec3'(0.78, 0.07, 0.06));
      Shaders.Set (Model, Identity);
      Meshes.Draw (Tower_M);
      declare
         Hub : constant Vec3 := Spot + Vec3'(0.0, 6.2, 0.0) + 2.4 * Front;
         Turn : constant Mat4 := Translation (Hub) * About (Front, 0.35 * Clock);
      begin
         Shaders.Set (Paint, Vec3'(0.55, 0.32, 0.18));
         Shaders.Set (Model, Turn);
         Meshes.Draw (Sails_M);
         Meshes.Draw (Lights_M);
      end;
   end Draw;

end Moulin;
