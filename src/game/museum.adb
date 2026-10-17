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

package body Museum is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;

   Pi : constant := Ada.Numerics.Pi;

   type Float_Array is array (Positive range <>) of Float;

   --  Materials (world.frag)
   Mat_Parquet  : constant := 35.0;
   Mat_Painting : constant := 44.0;   --  seed: which painting, uv across it
   Mat_Marble   : constant := 45.0;
   Mat_Damask   : constant := 46.0;   --  red fabric on the walls
   Mat_Skylight : constant := 47.0;
   Mat_Gilt     : constant := 48.0;   --  gilded frames
   Mat_Wood     : constant := 13.0;
   Mat_Stone    : constant := 29.0;
   Mat_Exit     : constant := 49.0;   --  the green SORTIE sign

   --  The gallery: along +X from the door (X 0) to the Mona Lisa (X 60),
   --  Z from -7 to 7, a storey high and a half; well under the Cour
   --  Napoléon, so nothing of the city reaches in
   Length : constant := 60.0;
   Half_W : constant := 7.0;
   Height : constant := 9.0;
   Depth  : constant := 45.0;

   Origin : Vec3 := (0.0, 0.0, 0.0);   --  the door, at floor level
   Built  : Boolean := False;
   Hall   : Meshes.Mesh;
   Clock  : Float := 0.0;

   function Pyramid return Vec3 is
      X, Z : Long_Float;
   begin
      Geo.To_Local (48.861052, 2.335846, X, Z);
      return (Float (X), Terrain.Height (Float (X), Float (Z)), Float (Z));
   end Pyramid;

   function Floor_Y return Float is (Origin.Y);

   function Touching_Pyramid (X, Z : Float) return Boolean is
      P : constant Vec3 := Pyramid;
   begin
      --  the glass is 35 m square; touching is being right at it
      return abs (X - P.X) < 19.5 and then abs (Z - P.Z) < 19.5;
   end Touching_Pyramid;

   procedure Entrance (X, Z, Yaw : out Float) is
   begin
      X := Origin.X + 3.0;
      Z := Origin.Z;
      Yaw := Pi / 2.0;   --  east, along the gallery
   end Entrance;

   procedure Way_Out (X, Z, Yaw : out Float) is
      P : constant Vec3 := Pyramid;
   begin
      X := P.X;
      Z := P.Z + 24.0;   --  south of it, on the Cour Napoléon
      Yaw := 0.0;        --  facing north, at the Pyramid
   end Way_Out;

   function At_Exit (X, Z : Float) return Boolean is
     (X - Origin.X < 1.2 and then abs (Z - Origin.Z) < 1.6);

   --  In gallery coordinates
   function G (X, Y, Z : Float) return Vec3 is (Origin + Vec3'(X, Y, Z));

   ---------------------------------------------------------------------------
   --  Building
   ---------------------------------------------------------------------------

   --  A quad with the corners put in order for the normal it should have
   procedure Face (A, B, C, D, N : Vec3; Mat : Float) is
      Got : constant Vec3 := Cross (B - A, D - A);
   begin
      if Dot (Got, N) >= 0.0 then
         Meshes.Quad (A, B, C, D, Mat);
      else
         Meshes.Quad (D, C, B, A, Mat);
      end if;
   end Face;

   --  An ellipsoid (faces outwards)
   procedure Blob (C : Vec3; RX, RY, RZ : Float; Mat : Float; Segs : Positive := 14) is
      Rings : constant Positive := Segs / 2 + 1;
      function P (I, J : Integer) return Vec3 is
         Phi   : constant Float := 2.0 * Pi * Float (I) / Float (Segs);
         Theta : constant Float := Pi * Float (J) / Float (Rings);
      begin
         return C + Vec3'(RX * Sin (Theta) * Cos (Phi), -RY * Cos (Theta),
                          RZ * Sin (Theta) * Sin (Phi));
      end P;
   begin
      for J in 0 .. Rings - 1 loop
         for I in 0 .. Segs - 1 loop
            declare
               M : constant Vec3 := 0.25 * (P (I, J) + P (I, J + 1) + P (I + 1, J + 1) + P (I + 1, J));
            begin
               Face (P (I, J), P (I, J + 1), P (I + 1, J + 1), P (I + 1, J), M - C, Mat);
            end;
         end loop;
      end loop;
   end Blob;

   --  A tapering column of rings between two heights (faces outwards);
   --  RX/RZ at the bottom and the top, and how far the top leans
   procedure Column (C : Vec3; Y0, Y1, RX0, RZ0, RX1, RZ1 : Float; Mat : Float;
                     Lean_X : Float := 0.0; Segs : Positive := 14) is
      function P (I : Integer; Top : Boolean) return Vec3 is
         A : constant Float := 2.0 * Pi * Float (I) / Float (Segs);
      begin
         return C + (if Top then Vec3'(Lean_X + RX1 * Cos (A), Y1, RZ1 * Sin (A))
                     else Vec3'(RX0 * Cos (A), Y0, RZ0 * Sin (A)));
      end P;
   begin
      for I in 0 .. Segs - 1 loop
         declare
            A : constant Float := 2.0 * Pi * (Float (I) + 0.5) / Float (Segs);
         begin
            Face (P (I, False), P (I + 1, False), P (I + 1, True), P (I, True),
                  (Cos (A), 0.0, Sin (A)), Mat);
         end;
      end loop;
   end Column;

   procedure Box (X0, X1, Y0, Y1, Z0, Z1 : Float; Mat : Float) is
      O : constant Vec3 := Origin;
   begin
      Meshes.Box (O.X + X0, O.X + X1, O.Y + Y0, O.Y + Y1, O.Z + Z0, O.Z + Z1, Mat);
   end Box;

   --  A painting on a wall, facing N, with its gilded frame
   procedure Painting (Centre : Vec3; Along, N : Vec3; W, H : Float; Id : Float) is
      Up : constant Vec3 := (0.0, 1.0, 0.0);
      C  : constant Vec3 := Centre + 0.06 * N;
      F  : constant Float := 0.12 + 0.02 * W;   --  frame width
   begin
      --  the canvas: u along, v up
      Meshes.Quad_UV (C - (W / 2.0) * Along - (H / 2.0) * Up,
                      C + (W / 2.0) * Along - (H / 2.0) * Up,
                      C + (W / 2.0) * Along + (H / 2.0) * Up,
                      C - (W / 2.0) * Along + (H / 2.0) * Up, N, Mat_Painting, Id);
      --  the frame: four gilt bars standing a little proud
      for Side in 1 .. 4 loop
         declare
            Ctr : constant Vec3 :=
              (case Side is
                  when 1 => Centre + ((H + F) / 2.0) * Up,
                  when 2 => Centre - ((H + F) / 2.0) * Up,
                  when 3 => Centre + ((W + F) / 2.0) * Along,
                  when others => Centre - ((W + F) / 2.0) * Along);
            Half_A : constant Float := (if Side <= 2 then W / 2.0 + F else F / 2.0);
            Half_U : constant Float := (if Side <= 2 then F / 2.0 else H / 2.0);
            A : constant Vec3 := Half_A * Along;
            U : constant Vec3 := Half_U * Up;
            T : constant Vec3 := 0.12 * N;
         begin
            Face (Ctr - A - U + T, Ctr + A - U + T, Ctr + A + U + T, Ctr - A + U + T, N, Mat_Gilt);
            Face (Ctr - A + U, Ctr + A + U, Ctr + A + U + T, Ctr - A + U + T, Up, Mat_Gilt);
            Face (Ctr - A - U, Ctr + A - U, Ctr + A - U + T, Ctr - A - U + T, (-1.0) * Up, Mat_Gilt);
         end;
      end loop;
   end Painting;

   procedure Create is
      P : constant Vec3 := Pyramid;
   begin
      Origin := (P.X - 10.0, P.Y - Depth, P.Z);
      Meshes.Start;

      --  floor, ceiling with skylights, walls in red damask with a stone dado
      Meshes.Quad_UV (G (0.0, 0.0, -Half_W), G (Length, 0.0, -Half_W), G (Length, 0.0, Half_W),
                      G (0.0, 0.0, Half_W), (0.0, 1.0, 0.0), Mat_Parquet, 0.0,
                      Length, 2.0 * Half_W);
      for K in 0 .. 5 loop
         declare
            X0 : constant Float := Float (K) * 10.0;
         begin
            Face (G (X0, Height, -Half_W), G (X0 + 10.0, Height, -Half_W),
                  G (X0 + 10.0, Height, Half_W), G (X0, Height, Half_W),
                  (0.0, -1.0, 0.0), Mat_Stone);
            Face (G (X0 + 2.0, Height - 0.02, -Half_W + 2.5), G (X0 + 8.0, Height - 0.02, -Half_W + 2.5),
                  G (X0 + 8.0, Height - 0.02, Half_W - 2.5), G (X0 + 2.0, Height - 0.02, Half_W - 2.5),
                  (0.0, -1.0, 0.0), Mat_Skylight);
         end;
      end loop;
      for Side in 1 .. 4 loop
         declare
            A, B : Vec3;
            N    : Vec3;
         begin
            case Side is
               when 1 => A := G (0.0, 0.0, -Half_W); B := G (Length, 0.0, -Half_W); N := (0.0, 0.0, 1.0);
               when 2 => A := G (Length, 0.0, Half_W); B := G (0.0, 0.0, Half_W); N := (0.0, 0.0, -1.0);
               when 3 => A := G (0.0, 0.0, Half_W); B := G (0.0, 0.0, -Half_W); N := (1.0, 0.0, 0.0);
               when others => A := G (Length, 0.0, -Half_W); B := G (Length, 0.0, Half_W); N := (-1.0, 0.0, 0.0);
            end case;
            Face (A, B, B + Vec3'(0.0, 1.1, 0.0), A + Vec3'(0.0, 1.1, 0.0), N, Mat_Stone);
            Face (A + Vec3'(0.0, 1.1, 0.0), B + Vec3'(0.0, 1.1, 0.0),
                  B + Vec3'(0.0, Height, 0.0), A + Vec3'(0.0, Height, 0.0), N, Mat_Damask);
         end;
      end loop;

      --  the door out, with its green SORTIE sign above
      Face (G (0.03, 0.0, -1.2), G (0.03, 0.0, 1.2), G (0.03, 2.8, 1.2), G (0.03, 2.8, -1.2),
            (1.0, 0.0, 0.0), Mat_Wood);
      Box (0.03, 0.12, 3.0, 3.45, -0.8, 0.8, Mat_Exit);

      --  the great paintings on the long walls
      Painting (G (14.0, 4.2, Half_W - 0.02), (-1.0, 0.0, 0.0), (0.0, 0.0, -1.0), 7.8, 6.1, 1.0);  --  Liberty
      Painting (G (34.0, 4.6, Half_W - 0.02), (-1.0, 0.0, 0.0), (0.0, 0.0, -1.0), 9.5, 6.7, 2.0);  --  the Medusa
      Painting (G (24.0, 4.5, -Half_W + 0.02), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), 11.0, 6.9, 3.0);  --  Coronation
      Painting (G (44.0, 3.4, -Half_W + 0.02), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), 3.0, 2.2, 4.0);   --  a still life

      --  The Mona Lisa: a grey wall of her own at the far end, small and far
      --  behind her glass, a wooden rail in a curve in front
      Box (Length - 0.6, Length - 0.05, 0.0, 6.0, -3.0, 3.0, Mat_Stone);
      Painting (G (Length - 0.62, 2.0, 0.0), (0.0, 0.0, 1.0), (-1.0, 0.0, 0.0), 0.53, 0.77, 0.0);
      for K in 0 .. 10 loop
         declare
            A0 : constant Float := Pi / 2.0 + Pi * Float (K) / 11.0;
            A1 : constant Float := Pi / 2.0 + Pi * Float (K + 1) / 11.0;
            R  : constant Float := 4.2;
            C  : constant Vec3 := G (Length - 0.6, 0.0, 0.0);
            P0 : constant Vec3 := C + Vec3'(R * Cos (A0), 0.95, R * Sin (A0));
            P1 : constant Vec3 := C + Vec3'(R * Cos (A1), 0.95, R * Sin (A1));
         begin
            Face (P0, P1, P1 + Vec3'(0.0, 0.12, 0.0), P0 + Vec3'(0.0, 0.12, 0.0),
                  (Cos (0.5 * (A0 + A1)), 0.0, Sin (0.5 * (A0 + A1))), Mat_Wood);
            Meshes.Box (P0.X - 0.05, P0.X + 0.05, Origin.Y, P0.Y, P0.Z - 0.05, P0.Z + 0.05, Mat_Wood);
         end;
      end loop;

      --  The Venus de Milo in the middle of the gallery: a pedestal, the
      --  drapery round her hips and legs, the torso turned a little, the
      --  head looking to her left, and no arms
      declare
         C : constant Vec3 := G (30.0, 0.0, 0.0);
      begin
         Box (29.3, 30.7, 0.0, 1.2, -0.7, 0.7, Mat_Stone);
         Column (C, 1.2, 2.25, 0.36, 0.3, 0.33, 0.25, Mat_Marble, Lean_X => 0.04);    --  drapery
         Blob (C + Vec3'(0.03, 2.3, 0.0), 0.33, 0.18, 0.24, Mat_Marble);              --  the knot of the drapery
         Column (C, 2.35, 2.95, 0.22, 0.17, 0.25, 0.17, Mat_Marble, Lean_X => 0.05);  --  torso
         Blob (C + Vec3'(0.1, 2.75, -0.12), 0.08, 0.08, 0.07, Mat_Marble, 10);       --  breasts
         Blob (C + Vec3'(0.1, 2.75, 0.12), 0.08, 0.08, 0.07, Mat_Marble, 10);
         Blob (C + Vec3'(0.06, 2.97, 0.0), 0.27, 0.07, 0.2, Mat_Marble);              --  shoulders
         Blob (C + Vec3'(0.05, 2.97, -0.27), 0.07, 0.08, 0.07, Mat_Marble, 10);      --  where the arms were
         Blob (C + Vec3'(0.05, 2.97, 0.27), 0.07, 0.08, 0.07, Mat_Marble, 10);
         Column (C + Vec3'(0.06, 0.0, 0.0), 2.97, 3.12, 0.06, 0.06, 0.06, 0.06, Mat_Marble, Segs => 8);
         Blob (C + Vec3'(0.08, 3.25, -0.03), 0.11, 0.14, 0.11, Mat_Marble);           --  head
         Blob (C + Vec3'(0.0, 3.32, -0.05), 0.09, 0.08, 0.09, Mat_Marble, 10);        --  her knot of hair
      end;

      --  The Winged Victory of Samothrace near the door: on the prow of a
      --  ship, striding into the wind, her wings spread back, no head
      declare
         C : constant Vec3 := G (8.0, 0.0, 0.0);
      begin
         Box (6.4, 9.6, 0.0, 0.6, -2.5, 2.5, Mat_Stone);          --  steps
         Box (7.0, 9.4, 0.6, 1.2, -2.0, 2.0, Mat_Stone);
         Box (7.4, 9.8, 1.2, 2.4, -1.0, 1.0, Mat_Stone);           --  the prow
         Box (9.8, 10.4, 1.3, 2.3, -0.6, 0.6, Mat_Stone);
         Column (C + Vec3'(0.9, 0.0, 0.0), 2.4, 3.6, 0.42, 0.32, 0.26, 0.22, Mat_Marble, Lean_X => 0.25);
         Column (C + Vec3'(0.9, 0.0, 0.0), 3.6, 4.3, 0.26, 0.22, 0.24, 0.24, Mat_Marble, Lean_X => 0.15);
         Blob (C + Vec3'(1.3, 4.3, 0.0), 0.28, 0.1, 0.3, Mat_Marble);
         for Side of Float_Array'(-1.0, 1.0) loop
            for F in 0 .. 5 loop
               declare
                  Root : constant Vec3 := C + Vec3'(1.0, 4.15 - 0.08 * Float (F), 0.18 * Side);
                  Tip  : constant Vec3 := Root + Vec3'(-1.25 + 0.12 * Float (F), 0.95 - 0.25 * Float (F),
                                                       (0.55 + 0.05 * Float (F)) * Side);
                  Lo   : constant Vec3 := (0.0, -0.32, 0.0);
               begin
                  Face (Root, Tip, Tip + Lo, Root + Lo, (0.0, 0.0, Side), Mat_Marble);
               end;
            end loop;
         end loop;
      end;

      Meshes.Finish (Hall);
      Built := True;
   end Create;

   ---------------------------------------------------------------------------

   procedure Keep_Inside (X, Z : in out Float) is
      LX : Float := X - Origin.X;
      LZ : Float := Z - Origin.Z;
      procedure Out_Of_Circle (CX, CZ, R : Float) is
         DX : constant Float := LX - CX;
         DZ : constant Float := LZ - CZ;
         D  : constant Float := Sqrt (DX * DX + DZ * DZ);
      begin
         if D < R and then D > 0.001 then
            LX := CX + DX / D * R;
            LZ := CZ + DZ / D * R;
         end if;
      end Out_Of_Circle;
   begin
      LX := Float'Max (0.4, Float'Min (Length - 0.4, LX));
      LZ := Float'Max (-Half_W + 0.4, Float'Min (Half_W - 0.4, LZ));
      Out_Of_Circle (30.0, 0.0, 1.3);    --  the Venus
      Out_Of_Circle (8.4, 0.0, 2.9);     --  the Victory's steps
      Out_Of_Circle (Length - 0.6, 0.0, 4.4);   --  the rail
      X := Origin.X + LX;
      Z := Origin.Z + LZ;
   end Keep_Inside;

   procedure Update (Dt : Float) is
   begin
      Clock := Clock + Dt;
   end Update;

   procedure Draw (Model, Paint, Skin, Legs, Gallery : GL.GLint) is
      Skins : constant array (0 .. 3) of Vec3 :=
        ((0.86, 0.68, 0.56), (0.76, 0.57, 0.44), (0.58, 0.40, 0.29), (0.40, 0.27, 0.19));
      Coats : constant array (0 .. 5) of Vec3 :=
        ((0.15, 0.2, 0.4), (0.6, 0.15, 0.15), (0.2, 0.2, 0.22), (0.85, 0.8, 0.7),
         (0.2, 0.45, 0.3), (0.7, 0.55, 0.2));
   begin
      if not Built then
         return;
      end if;
      Shaders.Set (Gallery, 1.0);
      Shaders.Set (Model, Identity);
      Meshes.Draw (Hall);
      --  the crowd at the rail, phones held up to the Mona Lisa
      Figures.Set_Locations ((Model, Paint, Skin, Legs));
      for K in 0 .. 13 loop
         declare
            Row  : constant Float := Float (K / 7);
            A    : constant Float := Pi / 2.0 + Pi * (Float (K mod 7) + 0.5 + 0.3 * Row) / 7.3;
            R    : constant Float := 4.75 + 0.85 * Row;
            P    : constant Vec3 := G (Length - 0.6 + R * Cos (A), 0.0, R * Sin (A));
            Sway : constant Float := 0.06 * Sin (Clock * 0.7 + Float (K) * 1.7);
         begin
            Figures.Person
              (Translation (P) * Rotation_Y (A + Pi / 2.0 + Sway),
               Coats (K mod 6), Skins ((K * 7) mod 4), (0.15, 0.15, 0.2),
               Arm_Up => (if K mod 3 /= 2 then -2.2 + 0.1 * Sin (Clock * 1.3 + Float (K)) else 0.0));
         end;
      end loop;
      Shaders.Set (Gallery, 0.0);
   end Draw;

end Museum;
