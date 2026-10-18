--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;

with Figures;
with Geo;
with Math3D;
with Meshes;
with Shaders;
with Terrain;

package body Market is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;

   Pi : constant := Ada.Numerics.Pi;

   --  Materials (world.frag)
   Mat_Planks : constant := 60.0;
   Mat_Glow   : constant := 61.0;   --  the lit inside of a stall
   Mat_Snow   : constant := 39.0;
   Mat_Fir    : constant := 37.0;
   Mat_Light  : constant := 38.0;   --  little lights (they glow at night)
   Mat_Wood   : constant := 13.0;
   Mat_Iron   : constant := 26.0;
   Wares : constant array (0 .. 5) of Float := (40.0, 46.0, 48.0, 37.0, 45.0, 38.0);

   Centre  : Vec3 := (0.0, 0.0, 0.0);
   Ring    : constant := 13.0;    --  the chalets stand on this circle
   Chalets : constant := 11;
   Gap     : constant := 2;       --  this one is left out: the way in, from the south

   Stalls : Meshes.Mesh;
   Built  : Boolean := False;
   Clock  : Float := 0.0;

   --  A quad with the corners put in order for the normal it should have
   procedure Face (A, B, C, D, N : Vec3; Mat : Float) is
   begin
      if Dot (Cross (B - A, D - A), N) >= 0.0 then
         Meshes.Quad (A, B, C, D, Mat);
      else
         Meshes.Quad (D, C, B, A, Mat);
      end if;
   end Face;

   --  A box in a frame: U along the front, V towards the back
   procedure Box (O, U, V : Vec3; X0, X1, Y0, Y1, Z0, Z1 : Float; Mat : Float) is
      Up : constant Vec3 := (0.0, 1.0, 0.0);
      function K (X, Y, Z : Float) return Vec3 is (O + X * U + Vec3'(0.0, Y, 0.0) + Z * V);
   begin
      Face (K (X0, Y0, Z0), K (X1, Y0, Z0), K (X1, Y1, Z0), K (X0, Y1, Z0), (-1.0) * V, Mat);
      Face (K (X0, Y0, Z1), K (X1, Y0, Z1), K (X1, Y1, Z1), K (X0, Y1, Z1), V, Mat);
      Face (K (X0, Y0, Z0), K (X0, Y0, Z1), K (X0, Y1, Z1), K (X0, Y1, Z0), (-1.0) * U, Mat);
      Face (K (X1, Y0, Z0), K (X1, Y0, Z1), K (X1, Y1, Z1), K (X1, Y1, Z0), U, Mat);
      Face (K (X0, Y1, Z0), K (X1, Y1, Z0), K (X1, Y1, Z1), K (X0, Y1, Z1), Up, Mat);
   end Box;

   --  One chalet, its front facing the middle of the square
   procedure Chalet (O, U, V : Vec3; Index : Natural) is
      W  : constant Float := 1.6;    --  half its width
      D  : constant Float := 2.2;    --  its depth
      H  : constant Float := 2.3;    --  the walls
      Rf : constant Float := 3.4;    --  the ridge
      function K (X, Y, Z : Float) return Vec3 is (O + X * U + Vec3'(0.0, Y, 0.0) + Z * V);
      Up : constant Vec3 := (0.0, 1.0, 0.0);
   begin
      --  the back and the sides in planks, a low front under the counter
      Box (O, U, V, -W, W, 0.0, H, D - 0.12, D, Mat_Planks);
      Box (O, U, V, -W, -W + 0.12, 0.0, H, 0.0, D, Mat_Planks);
      Box (O, U, V, W - 0.12, W, 0.0, H, 0.0, D, Mat_Planks);
      Box (O, U, V, -W, W, 0.0, 0.95, 0.0, 0.12, Mat_Planks);
      --  inside: lit, with shelves of wares
      Face (K (-W + 0.12, 0.95, D - 0.13), K (W - 0.12, 0.95, D - 0.13),
            K (W - 0.12, H, D - 0.13), K (-W + 0.12, H, D - 0.13), (-1.0) * V, Mat_Glow);
      Face (K (-W + 0.12, H - 0.01, 0.12), K (W - 0.12, H - 0.01, 0.12),
            K (W - 0.12, H - 0.01, D - 0.12), K (-W + 0.12, H - 0.01, D - 0.12), (-1.0) * Up, Mat_Glow);
      for Shelf in 0 .. 1 loop
         declare
            Y : constant Float := 1.25 + 0.5 * Float (Shelf);
         begin
            Box (O, U, V, -W + 0.15, W - 0.15, Y - 0.03, Y, D - 0.5, D - 0.13, Mat_Wood);
            for K2 in 0 .. 6 loop
               declare
                  X : constant Float := -W + 0.35 + Float (K2) * (2.0 * W - 0.7) / 6.0;
                  M : constant Float := Wares ((Index * 3 + K2 + Shelf) mod Wares'Length);
                  S : constant Float := 0.07 + 0.03 * Float ((K2 + Index) mod 3);
               begin
                  Box (O, U, V, X - S, X + S, Y, Y + 2.0 * S, D - 0.4, D - 0.4 + 2.0 * S, M);
               end;
            end loop;
         end;
      end loop;
      --  the counter, with wares on it too
      Box (O, U, V, -W - 0.05, W + 0.05, 0.95, 1.0, -0.25, 0.3, Mat_Wood);
      for K2 in 0 .. 3 loop
         declare
            X : constant Float := -W + 0.5 + Float (K2) * (2.0 * W - 1.0) / 3.0;
         begin
            Box (O, U, V, X - 0.1, X + 0.1, 1.0, 1.12, -0.1, 0.1,
                 Wares ((Index + K2 * 2) mod Wares'Length));
         end;
      end loop;
      --  the gables and the roof, overhanging at the front, with snow on it
      Face (K (-W, H, 0.0), K (-W, Rf, D / 2.0), K (-W, Rf, D / 2.0), K (-W, H, D), (-1.0) * U, Mat_Planks);
      Face (K (W, H, 0.0), K (W, Rf, D / 2.0), K (W, Rf, D / 2.0), K (W, H, D), U, Mat_Planks);
      for Side in 0 .. 1 loop
         declare
            Z_Eave : constant Float := (if Side = 0 then -0.6 else D + 0.25);
            Y_Eave : constant Float := H - (if Side = 0 then 0.55 else 0.2);
            Out_N  : constant Vec3 := Normalize ((if Side = 0 then (-1.0) else 1.0) * V + 0.9 * Up);
         begin
            Face (K (-W - 0.25, Y_Eave, Z_Eave), K (W + 0.25, Y_Eave, Z_Eave),
                  K (W + 0.25, Rf, D / 2.0), K (-W - 0.25, Rf, D / 2.0), Out_N, Mat_Wood);
            Face (K (-W - 0.25, Y_Eave + 0.08, Z_Eave), K (W + 0.25, Y_Eave + 0.08, Z_Eave),
                  K (W + 0.25, Rf + 0.08, D / 2.0), K (-W - 0.25, Rf + 0.08, D / 2.0), Out_N, Mat_Snow);
         end;
      end loop;
      --  a string of lights along the front eave
      for L in 0 .. 12 loop
         declare
            X : constant Float := -W - 0.2 + Float (L) * (2.0 * W + 0.4) / 12.0;
            Sag : constant Float := 0.12 * Sin (Pi * Float (L mod 6) / 6.0);
            P : constant Vec3 := K (X, H - 0.62 - Sag, -0.58);
         begin
            Meshes.Box (P.X - 0.035, P.X + 0.035, P.Y - 0.035, P.Y + 0.035, P.Z - 0.035, P.Z + 0.035,
                        Mat_Light);
         end;
      end loop;
   end Chalet;

   --  The tree: cones of fir one above the other, lights round it, a star
   procedure Tree (C : Vec3) is
      procedure Cone (R, Y0, Y1 : Float) is
         Segs : constant := 18;
         Apex : constant Vec3 := C + Vec3'(0.0, Y1, 0.0);
      begin
         for I in 0 .. Segs - 1 loop
            declare
               A0 : constant Float := 2.0 * Pi * Float (I) / Float (Segs);
               A1 : constant Float := 2.0 * Pi * Float (I + 1) / Float (Segs);
               P0 : constant Vec3 := C + Vec3'(R * Cos (A0), Y0, R * Sin (A0));
               P1 : constant Vec3 := C + Vec3'(R * Cos (A1), Y0, R * Sin (A1));
            begin
               --  triangles as quads with the doubled corner in the middle,
               --  so the normal comes out right whichever way they turn
               Face (P0, Apex, Apex, P1, Vec3'(Cos (0.5 * (A0 + A1)), 0.4, Sin (0.5 * (A0 + A1))), Mat_Fir);
               Face (P0, C + Vec3'(0.0, Y0, 0.0), C + Vec3'(0.0, Y0, 0.0), P1, (0.0, -1.0, 0.0), Mat_Fir);
            end;
         end loop;
      end Cone;
   begin
      Meshes.Box (C.X - 0.2, C.X + 0.2, C.Y, C.Y + 1.5, C.Z - 0.2, C.Z + 0.2, Mat_Wood);
      Cone (3.2, 1.2, 6.0);
      Cone (2.5, 4.0, 8.5);
      Cone (1.7, 6.6, 10.8);
      --  a spiral of lights round it
      for L in 0 .. 70 loop
         declare
            T : constant Float := Float (L) / 70.0;
            Y : constant Float := 1.5 + 9.0 * T;
            R : constant Float := 3.0 * (1.0 - T) + 0.25;
            A : constant Float := 2.0 * Pi * 5.0 * T;
            P : constant Vec3 := C + Vec3'(R * Cos (A), Y, R * Sin (A));
         begin
            Meshes.Box (P.X - 0.06, P.X + 0.06, P.Y - 0.06, P.Y + 0.06, P.Z - 0.06, P.Z + 0.06, Mat_Light);
         end;
      end loop;
      Meshes.Box (C.X - 0.3, C.X + 0.3, C.Y + 10.7, C.Y + 11.4, C.Z - 0.08, C.Z + 0.08, Mat_Light);
      Meshes.Box (C.X - 0.08, C.X + 0.08, C.Y + 10.7, C.Y + 11.4, C.Z - 0.3, C.Z + 0.3, Mat_Light);
   end Tree;

   procedure Create is
      X, Z : Long_Float;
   begin
      Geo.To_Local (48.886545, 2.340785, X, Z);
      Centre := (Float (X), Terrain.Height (Float (X), Float (Z)), Float (Z));
      Meshes.Start;
      for I in 0 .. Chalets - 1 loop
         if I /= Gap then
            declare
               A : constant Float := 2.0 * Pi * Float (I) / Float (Chalets) + Pi / 2.0;
               V : constant Vec3 := (Cos (A), 0.0, Sin (A));        --  outwards: towards its back
               U : constant Vec3 := (-Sin (A), 0.0, Cos (A));
               P : constant Vec3 := Centre + Ring * V;
            begin
               Chalet ((P.X, Terrain.Height (P.X, P.Z), P.Z), U, V, I);
            end;
         end if;
      end loop;
      Tree (Centre);
      --  lanterns on posts between the chalets
      for I in 0 .. Chalets - 1 loop
         declare
            A : constant Float := 2.0 * Pi * (Float (I) + 0.5) / Float (Chalets) + Pi / 2.0;
            P : constant Vec3 := Centre + (Ring - 1.2) * Vec3'(Cos (A), 0.0, Sin (A));
            G : constant Float := Terrain.Height (P.X, P.Z);
         begin
            Meshes.Box (P.X - 0.05, P.X + 0.05, G, G + 2.6, P.Z - 0.05, P.Z + 0.05, Mat_Iron);
            Meshes.Box (P.X - 0.15, P.X + 0.15, G + 2.6, G + 2.95, P.Z - 0.15, P.Z + 0.15, Mat_Glow);
         end;
      end loop;
      Meshes.Finish (Stalls);
      Built := True;
   end Create;

   procedure Update (Dt : Float) is
   begin
      Clock := Clock + Dt;
   end Update;

   function Nearness (X, Z : Float) return Float is
     (Float'Max (0.0, 1.0 - Sqrt ((X - Centre.X) ** 2 + (Z - Centre.Z) ** 2) / 60.0));

   procedure Draw (Model, Paint, Skin, Legs : GL.GLint) is
      Coats : constant array (0 .. 6) of Vec3 :=
        ((0.55, 0.08, 0.1), (0.12, 0.15, 0.3), (0.2, 0.2, 0.22), (0.45, 0.3, 0.18),
         (0.15, 0.32, 0.2), (0.75, 0.7, 0.62), (0.35, 0.12, 0.35));
      Skins : constant array (0 .. 3) of Vec3 :=
        ((0.86, 0.68, 0.56), (0.76, 0.57, 0.44), (0.58, 0.40, 0.29), (0.40, 0.27, 0.19));
   begin
      if not Built then
         return;
      end if;
      Shaders.Set (Model, Identity);
      Meshes.Draw (Stalls);
      --  people strolling round between the tree and the stalls, and a few
      --  standing at the counters with a cup of vin chaud
      Figures.Set_Locations ((Model, Paint, Skin, Legs));
      for K in 0 .. 27 loop
         declare
            Dir   : constant Float := (if K mod 2 = 0 then 1.0 else -1.0);
            Speed : constant Float := 0.07 + 0.012 * Float (K mod 5);
            R     : Float := 6.5 + 2.8 * Float (K mod 3);
            A     : Float := 2.0 * Pi * Float (K) / 28.0 + Dir * Speed * Clock;
            Still : constant Boolean := K mod 4 = 3;
            Face_A : Float;
         begin
            if Still then
               --  at a counter, facing it
               A := 2.0 * Pi * Float (K / 4 mod Chalets) / Float (Chalets) + Pi / 2.0 + 0.2;
               R := Ring - 0.95;
               Face_A := A + Pi / 2.0;
            else
               Face_A := A + Dir * Pi / 2.0 + Pi / 2.0;
            end if;
            declare
               P : constant Vec3 := Centre + R * Vec3'(Cos (A), 0.0, Sin (A));
            begin
               Figures.Person
                 (Translation ((P.X, Terrain.Height (P.X, P.Z), P.Z)) * Rotation_Y (-Face_A + Pi / 2.0),
                  Coats (K mod 7), Skins ((K * 3) mod 4), (0.14, 0.14, 0.17),
                  Stride => (if Still then 0.0 else 0.35 * Sin (Clock * 4.5 + Float (K))),
                  Hat    => (if K mod 5 = 1 then Figures.Cap else Figures.None),
                  Hat_Colour => (0.6, 0.1, 0.1),
                  Arm_Up => (if K mod 3 = 0 then -1.2 else 0.0));   --  a cup in hand
            end;
         end;
      end loop;
   end Draw;

end Market;
