--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Containers.Ordered_Maps;
with Ada.Containers.Vectors;
with Ada.Environment_Variables;
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Numerics.Float_Random;

with Meshes;
with Road_Network;
with Shaders;
with Terrain;
with World;

package body Street_Life is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;

   Pi : constant := Ada.Numerics.Pi;

   type Float_List is array (Positive range <>) of Float;

   --  Materials (world.frag)
   Mat_Iron    : constant := 26.0;   --  painted cast iron, lamp-post grey
   Mat_Tyre    : constant := 17.0;
   Mat_Wood    : constant := 13.0;
   Mat_Marble  : constant := 45.0;
   Mat_Poster  : constant := 55.0;
   Mat_Green   : constant := 56.0;   --  Paris green cast iron
   Mat_Tag     : constant := 57.0;
   Mat_Paper   : constant := 58.0;
   Mat_Kerb    : constant := 2.0;
   Mat_Cover   : constant := 67.0;
   Mat_Grate   : constant := 68.0;
   Mat_Gutter  : constant := 69.0;
   Mat_Mouth   : constant := 70.0;
   Mat_Rubber  : constant := 71.0;
   Mat_Pair    : constant := 72.0;

   --  A seed for this game: the tags and posters are somewhere else next time
   Gen : Ada.Numerics.Float_Random.Generator;
   Session : Float := 0.0;
   Started : Boolean := False;

   procedure Begin_Session is
   begin
      if not Started then
         Ada.Numerics.Float_Random.Reset (Gen);
         Session := 1000.0 * Ada.Numerics.Float_Random.Random (Gen);
         Started := True;
      end if;
   end Begin_Session;

   function Rnd return Float is (Ada.Numerics.Float_Random.Random (Gen));

   --  How often the rarest detail turns up (PARIS_RARE=1: often, testing)
   Rare : constant Float := (if Ada.Environment_Variables.Exists ("PARIS_RARE") then 0.5 else 0.012);

   --  0 .. 1 from a few numbers, always the same for the same numbers
   function Hash (A, B, C, D : Float) return Float is
      V : constant Float := Sin (A * 12.9898 + B * 78.233 + C * 37.719 + D * 4.581) * 43758.5453;
   begin
      return V - Float'Floor (V);
   end Hash;

   ---------------------------------------------------------------------------
   --  Building shapes: in a local frame on the pavement, X along the
   --  street, Y up, Z towards the road
   ---------------------------------------------------------------------------

   type Frame is record
      P, U, V : Vec3;
   end record;

   function At_F (F : Frame; X, Y, Z : Float) return Vec3 is
     (F.P + X * F.U + Vec3'(0.0, Y, 0.0) + Z * F.V);

   --  A quad with the corners put in order for the normal it should have
   procedure Face (A, B, C, D, N : Vec3; Mat : Float) is
   begin
      if Dot (Cross (B - A, D - A), N) >= 0.0 then
         Meshes.Quad (A, B, C, D, Mat);
      else
         Meshes.Quad (D, C, B, A, Mat);
      end if;
   end Face;

   procedure Box (F : Frame; X0, X1, Y0, Y1, Z0, Z1 : Float; Mat : Float) is
      function K (X, Y, Z : Float) return Vec3 is (At_F (F, X, Y, Z));
      Up : constant Vec3 := (0.0, 1.0, 0.0);
   begin
      Face (K (X0, Y0, Z1), K (X1, Y0, Z1), K (X1, Y1, Z1), K (X0, Y1, Z1), F.V, Mat);
      Face (K (X0, Y0, Z0), K (X1, Y0, Z0), K (X1, Y1, Z0), K (X0, Y1, Z0), (-1.0) * F.V, Mat);
      Face (K (X1, Y0, Z0), K (X1, Y0, Z1), K (X1, Y1, Z1), K (X1, Y1, Z0), F.U, Mat);
      Face (K (X0, Y0, Z0), K (X0, Y0, Z1), K (X0, Y1, Z1), K (X0, Y1, Z0), (-1.0) * F.U, Mat);
      Face (K (X0, Y1, Z0), K (X1, Y1, Z0), K (X1, Y1, Z1), K (X0, Y1, Z1), Up, Mat);
      Face (K (X0, Y0, Z0), K (X1, Y0, Z0), K (X1, Y0, Z1), K (X0, Y0, Z1), (-1.0) * Up, Mat);
   end Box;

   --  A round post or drum (a cone when the radii differ), with a lid
   procedure Drum (F : Frame; CX, CZ, Y0, Y1, R0, R1 : Float; Mat : Float;
                   Segs : Positive := 10; Lid : Boolean := True) is
      function P (I : Integer; Top : Boolean) return Vec3 is
         A : constant Float := 2.0 * Pi * Float (I) / Float (Segs);
         R : constant Float := (if Top then R1 else R0);
      begin
         return At_F (F, CX + R * Cos (A), (if Top then Y1 else Y0), CZ + R * Sin (A));
      end P;
      C : constant Vec3 := At_F (F, CX, Y1, CZ);
   begin
      for I in 0 .. Segs - 1 loop
         declare
            A : constant Float := 2.0 * Pi * (Float (I) + 0.5) / Float (Segs);
         begin
            Face (P (I, False), P (I + 1, False), P (I + 1, True), P (I, True),
                  Cos (A) * F.U + Sin (A) * F.V, Mat);
            if Lid then
               Face (C, P (I, True), P (I + 1, True), P (I + 1, True), (0.0, 1.0, 0.0), Mat);
            end if;
         end;
      end loop;
   end Drum;

   --  A bar between two points (world)
   procedure Bar (P0, P1 : Vec3; R : Float; Mat : Float; Segs : Positive := 6) is
      D : constant Vec3 := Normalize (P1 - P0);
      A : constant Vec3 :=
        Normalize (Cross (D, (if abs D.Y < 0.9 then Vec3'(0.0, 1.0, 0.0) else Vec3'(1.0, 0.0, 0.0))));
      B : constant Vec3 := Cross (D, A);
      function Rim (I : Integer) return Vec3 is
         T : constant Float := 2.0 * Pi * Float (I) / Float (Segs);
      begin
         return R * (Cos (T) * A + Sin (T) * B);
      end Rim;
   begin
      for I in 0 .. Segs - 1 loop
         Face (P0 + Rim (I), P1 + Rim (I), P1 + Rim (I + 1), P0 + Rim (I + 1), Rim (I) + Rim (I + 1), Mat);
      end loop;
   end Bar;

   --  Solid things the car can hit: circles on the ground
   type Solid is record
      X, Z, R : Float;
   end record;
   package Solid_Vectors is new Ada.Containers.Vectors (Positive, Solid);

   procedure Solid_At (List : in out Solid_Vectors.Vector; F : Frame; X, Z, R : Float) is
      P : constant Vec3 := At_F (F, X, 0.0, Z);
   begin
      List.Append ((P.X, P.Z, R));
   end Solid_At;

   ---------------------------------------------------------------------------
   --  The street furniture
   ---------------------------------------------------------------------------

   --  A Paris litter bin: a green post, a hoop, the bag hanging in it
   procedure Bin (F : Frame; L : in out Solid_Vectors.Vector) is
   begin
      Drum (F, 0.0, -0.25, 0.0, 1.05, 0.035, 0.035, Mat_Green, 6);
      Drum (F, 0.0, 0.0, 0.8, 0.86, 0.23, 0.23, Mat_Green, 12, Lid => False);
      Drum (F, 0.0, 0.0, 0.3, 0.8, 0.17, 0.21, Mat_Green, 12);
      Solid_At (L, F, 0.0, 0.0, 0.3);
   end Bin;

   --  A bench facing the road: iron legs, wooden slats, a back
   procedure Bench (F : Frame; L : in out Solid_Vectors.Vector) is
   begin
      for X of Float_List'(-0.75, 0.75) loop
         Box (F, X - 0.04, X + 0.04, 0.0, 0.45, -0.22, 0.22, Mat_Iron);
         Box (F, X - 0.04, X + 0.04, 0.45, 0.9, -0.3, -0.24, Mat_Iron);
      end loop;
      for K in 0 .. 2 loop
         Box (F, -0.95, 0.95, 0.43, 0.47, -0.2 + 0.14 * Float (K), -0.09 + 0.14 * Float (K), Mat_Wood);
      end loop;
      for K in 0 .. 1 loop
         Box (F, -0.95, 0.95, 0.58 + 0.16 * Float (K), 0.7 + 0.16 * Float (K), -0.3, -0.26, Mat_Wood);
      end loop;
      Solid_At (L, F, -0.6, 0.0, 0.45);
      Solid_At (L, F, 0.6, 0.0, 0.45);
   end Bench;

   --  A row of bollards along the kerb
   procedure Bollards (F : Frame; L : in out Solid_Vectors.Vector) is
   begin
      for K in -2 .. 2 loop
         declare
            X : constant Float := 1.3 * Float (K);
         begin
            Drum (F, X, 0.0, 0.0, 0.85, 0.06, 0.05, Mat_Iron, 8);
            Drum (F, X, 0.0, 0.62, 0.68, 0.075, 0.075, Mat_Iron, 8);   --  the ring
            Solid_At (L, F, X, 0.0, 0.12);
         end;
      end loop;
   end Bollards;

   --  A Morris column: a green drum covered in posters, a little dome
   procedure Morris (F : Frame; Seed : Float; L : in out Solid_Vectors.Vector) is
      Segs : constant := 16;
   begin
      Drum (F, 0.0, 0.0, 0.0, 0.4, 0.72, 0.68, Mat_Green, Segs);
      --  the posters: eight panels round the drum, two rows of them
      for I in 0 .. 7 loop
         for Row in 0 .. 1 loop
            declare
               A0 : constant Float := 2.0 * Pi * Float (I) / 8.0;
               A1 : constant Float := 2.0 * Pi * Float (I + 1) / 8.0;
               R  : constant Float := 0.66;
               Y0 : constant Float := 0.45 + 1.25 * Float (Row);
               P0 : constant Vec3 := At_F (F, R * Cos (A0), Y0, R * Sin (A0));
               P1 : constant Vec3 := At_F (F, R * Cos (A1), Y0, R * Sin (A1));
               Up : constant Vec3 := (0.0, 1.22, 0.0);
               N  : constant Vec3 := Cos (0.5 * (A0 + A1)) * F.U + Sin (0.5 * (A0 + A1)) * F.V;
            begin
               Meshes.Quad_UV (P0, P1, P1 + Up, P0 + Up, N, Mat_Poster, Seed + Float (I * 2 + Row));
            end;
         end loop;
      end loop;
      Drum (F, 0.0, 0.0, 2.95, 3.25, 0.7, 0.7, Mat_Green, Segs);
      Drum (F, 0.0, 0.0, 3.25, 3.9, 0.72, 0.12, Mat_Green, Segs);
      Drum (F, 0.0, 0.0, 3.9, 4.3, 0.05, 0.03, Mat_Green, 6);
      Solid_At (L, F, 0.0, 0.0, 0.75);
   end Morris;

   --  A newspaper kiosk: a green booth, posters on the sides, a dome
   procedure Kiosk (F : Frame; Seed : Float; L : in out Solid_Vectors.Vector) is
   begin
      Box (F, -1.2, 1.2, 0.0, 2.5, -0.8, 0.8, Mat_Green);
      Box (F, -1.4, 1.4, 2.5, 2.65, -1.0, 1.0, Mat_Green);
      Drum (F, 0.0, 0.0, 2.65, 3.3, 0.9, 0.15, Mat_Green, 8);
      --  the papers and magazines on show at the front
      Meshes.Quad_UV (At_F (F, -1.0, 0.7, 0.82), At_F (F, 1.0, 0.7, 0.82),
                      At_F (F, 1.0, 1.9, 0.82), At_F (F, -1.0, 1.9, 0.82), F.V, Mat_Paper, 0.0, 3.0, 2.0);
      --  posters on the ends
      for Side of Float_List'(-1.0, 1.0) loop
         Meshes.Quad_UV (At_F (F, Side * 1.22, 0.8, -0.6), At_F (F, Side * 1.22, 0.8, 0.6),
                         At_F (F, Side * 1.22, 2.3, 0.6), At_F (F, Side * 1.22, 0.8 + 1.5, -0.6),
                         Side * F.U, Mat_Poster, Seed + Side, 1.0, 1.0);
      end loop;
      Solid_At (L, F, -0.7, 0.0, 0.95);
      Solid_At (L, F, 0.7, 0.0, 0.95);
   end Kiosk;

   --  A Wallace fountain: a plinth, four slender figures holding a dome
   procedure Wallace (F : Frame; L : in out Solid_Vectors.Vector) is
   begin
      Drum (F, 0.0, 0.0, 0.0, 0.55, 0.42, 0.36, Mat_Green, 8);
      for K in 0 .. 3 loop
         declare
            A : constant Float := Pi / 4.0 + Pi / 2.0 * Float (K);
         begin
            Drum (F, 0.2 * Cos (A), 0.2 * Sin (A), 0.55, 1.9, 0.08, 0.06, Mat_Green, 6);
         end;
      end loop;
      Drum (F, 0.0, 0.0, 1.9, 2.0, 0.36, 0.36, Mat_Green, 12);
      Drum (F, 0.0, 0.0, 2.0, 2.55, 0.36, 0.05, Mat_Green, 12);
      Solid_At (L, F, 0.0, 0.0, 0.45);
   end Wallace;

   --  A café terrace: round marble tables, chairs in pairs
   procedure Terrace (F : Frame; L : in out Solid_Vectors.Vector) is
   begin
      for T in -1 .. 1 loop
         declare
            X : constant Float := 2.4 * Float (T);
         begin
            Drum (F, X, 0.0, 0.0, 0.72, 0.04, 0.04, Mat_Iron, 6);
            Drum (F, X, 0.0, 0.72, 0.75, 0.32, 0.32, Mat_Marble, 12);
            for Side of Float_List'(-1.0, 1.0) loop
               declare
                  CX : constant Float := X + Side * 0.55;
               begin
                  Box (F, CX - 0.2, CX + 0.2, 0.43, 0.47, -0.2, 0.2, Mat_Wood);
                  Box (F, CX + Side * 0.18, CX + Side * 0.22, 0.47, 0.9, -0.2, 0.2, Mat_Wood);
                  for LX of Float_List'(-0.17, 0.17) loop
                     for LZ of Float_List'(-0.17, 0.17) loop
                        Box (F, CX + LX - 0.015, CX + LX + 0.015, 0.0, 0.43, LZ - 0.015, LZ + 0.015, Mat_Iron);
                     end loop;
                  end loop;
               end;
            end loop;
            Solid_At (L, F, X, 0.0, 0.5);
         end;
      end loop;
   end Terrace;

   --  A bicycle leaning on a post
   procedure Bicycle (F : Frame) is
      Lean : constant Float := 0.18;
      function W (X, Y : Float) return Vec3 is (At_F (F, X, Y, -Lean * Y));
      procedure Wheel (CX : Float) is
         Segs : constant := 14;
      begin
         for I in 0 .. Segs - 1 loop
            declare
               A0 : constant Float := 2.0 * Pi * Float (I) / Float (Segs);
               A1 : constant Float := 2.0 * Pi * Float (I + 1) / Float (Segs);
            begin
               Bar (W (CX + 0.34 * Cos (A0), 0.34 + 0.34 * Sin (A0)),
                    W (CX + 0.34 * Cos (A1), 0.34 + 0.34 * Sin (A1)), 0.025, Mat_Tyre, 4);
            end;
         end loop;
      end Wheel;
   begin
      Wheel (-0.52);
      Wheel (0.52);
      Bar (W (-0.52, 0.34), W (-0.05, 0.36), 0.018, Mat_Iron, 4);      --  chain stay
      Bar (W (-0.05, 0.36), W (-0.15, 0.85), 0.02, Mat_Iron, 4);       --  seat tube
      Bar (W (-0.52, 0.34), W (-0.15, 0.85), 0.016, Mat_Iron, 4);      --  seat stay
      Bar (W (-0.15, 0.82), W (0.42, 0.85), 0.02, Mat_Iron, 4);        --  top tube
      Bar (W (-0.05, 0.36), W (0.42, 0.85), 0.022, Mat_Iron, 4);       --  down tube
      Bar (W (0.42, 0.85), W (0.52, 0.34), 0.018, Mat_Iron, 4);        --  fork
      Bar (W (0.42, 0.85), W (0.38, 1.02), 0.018, Mat_Iron, 4);
      Bar (W (0.38, 1.02) - 0.25 * F.V, W (0.38, 1.02) + 0.25 * F.V, 0.015, Mat_Tyre, 4);   --  handlebar
      Box (F, -0.27, -0.05, 0.86, 0.9, -0.06 - Lean * 0.88, 0.06 - Lean * 0.88, Mat_Tyre);   --  saddle
      Drum (F, 0.0, -0.35, 0.0, 1.0, 0.04, 0.04, Mat_Iron, 6);         --  the post
   end Bicycle;

   ---------------------------------------------------------------------------
   --  Cells
   ---------------------------------------------------------------------------

   Cell_Size : constant := 64.0;
   Reach     : constant := 230.0;   --  drawn this far
   Let_Go    : constant := 330.0;   --  freed beyond

   type Cell_Key is record
      CX, CZ : Integer;
   end record;

   function "<" (A, B : Cell_Key) return Boolean is
     (A.CX < B.CX or else (A.CX = B.CX and then A.CZ < B.CZ));

   package Vec_Vectors is new Ada.Containers.Vectors (Positive, Vec3);

   type Cell is record
      Mesh   : Meshes.Mesh;
      Solids : Solid_Vectors.Vector;
      Floats : Vec_Vectors.Vector;   --  things bobbing in the air (drawn apart)
   end record;

   package Cell_Maps is new Ada.Containers.Ordered_Maps (Cell_Key, Cell);
   Cells : Cell_Maps.Map;

   procedure Build_Cell (K : Cell_Key; C : out Cell) is
      X0 : constant Float := Float (K.CX) * Cell_Size;
      Z0 : constant Float := Float (K.CZ) * Cell_Size;
      Mid_X : constant Float := X0 + Cell_Size / 2.0;
      Mid_Z : constant Float := Z0 + Cell_Size / 2.0;

      function Mine (X, Z : Float) return Boolean is
        (X >= X0 and then X < X0 + Cell_Size and then Z >= Z0 and then Z < Z0 + Cell_Size);

      --  In the road: covers, and at the kerbs grates, openings and, on some
      --  streets, water running in the gutter
      procedure Ground_Details (AX, AZ, DX, DZ, L, Width : Float) is
         Up : constant Vec3 := (0.0, 1.0, 0.0);
         D  : constant Vec3 := (DX, 0.0, DZ);
         function G (T, Side : Float; Y : Float := 0.0) return Vec3 is
            X : constant Float := AX + T * DX - Side * DZ;
            Z : constant Float := AZ + T * DZ + Side * DX;
         begin
            return (X, Terrain.Height (X, Z) + Y, Z);
         end G;
         Wet : constant Boolean :=
           Hash (Float'Rounding (AX), Float'Rounding (AZ), Session, 13.0) < 0.3;
         Downhill : constant Boolean := Terrain.Height (AX + L * DX, AZ + L * DZ) <= Terrain.Height (AX, AZ);
         T : Float := 9.0;
      begin
         if not Mine (AX + 0.5 * L * DX, AZ + 0.5 * L * DZ) then
            return;
         end if;
         --  covers in the carriageway
         while T < L - 4.0 loop
            declare
               H  : constant Float := Hash (Float'Rounding (AX + T), Float'Rounding (AZ), 3.0, T);
               Sd : constant Float := (H - 0.5) * Width * 0.5;
            begin
               if H < 0.5 then
                  declare
                     C : constant Vec3 := G (T, Sd, 0.03);
                  begin
                     Meshes.Quad_UV (C - 0.4 * D - 0.4 * Vec3'(-DZ, 0.0, DX), C + 0.4 * D - 0.4 * Vec3'(-DZ, 0.0, DX),
                                     C + 0.4 * D + 0.4 * Vec3'(-DZ, 0.0, DX), C - 0.4 * D + 0.4 * Vec3'(-DZ, 0.0, DX),
                                     Up, Mat_Cover, 0.0);
                  end;
               end if;
            end;
            T := T + 23.0;
         end loop;
         for Side of Float_List'(-1.0, 1.0) loop
            declare
               Edge : constant Float := Width / 2.0;
               Out_V : constant Vec3 := Side * Vec3'(-DZ, 0.0, DX);   --  towards the pavement
            begin
               --  the water, in pieces that follow the ground, flowing downhill
               if Wet then
                  declare
                     U : Float := 3.0;
                  begin
                     while U < L - 3.0 loop
                        declare
                           U1 : constant Float := Float'Min (L - 3.0, U + 4.0);
                           A0 : constant Vec3 := G (U, Side * (Edge - 0.36), 0.025);
                           A1 : constant Vec3 := G (U1, Side * (Edge - 0.36), 0.025);
                           B0 : constant Vec3 := G (U, Side * (Edge - 0.04), 0.025);
                           B1 : constant Vec3 := G (U1, Side * (Edge - 0.04), 0.025);
                           --  the seed is the way it flows (the shader runs it on
                           --  from piece to piece)
                           Flow : constant Float :=
                             (if Downhill then Arctan (DZ, DX) else Arctan (-DZ, -DX));
                        begin
                           Meshes.Quad_UV (A0, A1, B1, B0, Up, Mat_Gutter, Flow, 1.0, 1.0);
                        end;
                        U := U + 4.0;
                     end loop;
                  end;
               end if;
               --  an opening in a kerb stone, a grate in the gutter before it
               declare
                  V : Float := 14.0 + 9.0 * Hash (AX, AZ, Side, 2.0);
                  K : Natural := 0;
               begin
                  while V < L - 6.0 loop
                     declare
                        Mid  : constant Vec3 := G (V, Side * Edge);
                        H    : constant Float := Hash (Float'Rounding (Mid.X), Float'Rounding (Mid.Z), Session, 11.0);
                        F    : constant Frame := (P => Mid, U => D, V => Out_V);   --  V: away from the road
                     begin
                        Box (F, -0.5, 0.5, 0.0, 0.17, 0.0, 0.32, Mat_Kerb);
                        Meshes.Quad (At_F (F, -0.32, 0.03, -0.005), At_F (F, 0.32, 0.03, -0.005),
                                     At_F (F, 0.32, 0.13, -0.005), At_F (F, -0.32, 0.13, -0.005), Mat_Mouth);
                        Meshes.Quad_UV (At_F (F, -0.3, 0.03, -0.42), At_F (F, 0.3, 0.03, -0.42),
                                        At_F (F, 0.3, 0.03, -0.04), At_F (F, -0.3, 0.03, -0.04),
                                        Up, Mat_Grate, 0.0);
                        if H < Rare then
                           --  a rare one: something in there
                           for E of Float_List'(-0.06, 0.06) loop
                              Meshes.Quad_UV (At_F (F, E - 0.012, 0.075, -0.008), At_F (F, E + 0.012, 0.075, -0.008),
                                              At_F (F, E + 0.012, 0.092, -0.008), At_F (F, E - 0.012, 0.092, -0.008),
                                              (-1.0) * Out_V, Mat_Pair, H * 50.0);
                           end loop;
                           C.Floats.Append (At_F (F, 0.15, 0.0, -0.6));
                        end if;
                     end;
                     V := V + 31.0;
                     K := K + 1;
                  end loop;
                  pragma Unreferenced (K);
               end;
            end;
         end loop;
      end Ground_Details;

      --  along a street: every 7 m on each side, a chance of something
      procedure Street (AX, AZ, BX, BZ, Width : Float; Named : Boolean) is
         L  : constant Float := Sqrt ((BX - AX) ** 2 + (BZ - AZ) ** 2);
         DX : constant Float := (BX - AX) / Float'Max (L, 0.01);
         DZ : constant Float := (BZ - AZ) / Float'Max (L, 0.01);
         T  : Float := 6.0;
         K2 : Natural := 0;
      begin
         if Width < 5.0 or else L < 14.0 then
            return;
         end if;
         while T <= L - 6.0 loop
            for Side of Float_List'(-1.0, 1.0) loop
               declare
                  Kerb : constant Float := Width / 2.0 + 0.7;
                  RX : constant Float := -DZ * Side;   --  out from the road
                  RZ : constant Float := DX * Side;
                  PX : constant Float := AX + T * DX + Kerb * RX;
                  PZ : constant Float := AZ + T * DZ + Kerb * RZ;
                  H  : constant Float := Hash (Float'Rounding (AX), Float'Rounding (AZ), Side, Float (K2));
                  HS : constant Float := Hash (Float'Rounding (PX), Float'Rounding (PZ), Session, 7.0);
                  F  : Frame;
               begin
                  if Mine (PX, PZ) and then not World.On_Road (PX, PZ) then
                     F := (P => (PX, Terrain.Height (PX, PZ), PZ),
                           U => (DX, 0.0, DZ),
                           V => (-RX, 0.0, -RZ));   --  towards the road
                     if H < 0.10 and then Width >= 6.0 then
                        Bin (F, C.Solids);
                     elsif H < 0.16 and then Width >= 9.0 then
                        Bench (F, C.Solids);
                     elsif H < 0.18 then
                        Bollards (F, C.Solids);
                     elsif H < 0.202 and then Width >= 9.0 then
                        Morris (F, 100.0 * H + Session, C.Solids);
                     elsif H < 0.21 and then Width >= 9.0 then
                        Kiosk (F, 100.0 * H + Session, C.Solids);
                     elsif H < 0.216 and then Width >= 7.0 then
                        Wallace (F, C.Solids);
                     elsif H < 0.27 and then Width >= 8.0 and then Named then
                        --  a terrace further from the kerb, by the cafés
                        F.P := F.P + 1.4 * Vec3'(RX, 0.0, RZ);
                        Terrace (F, C.Solids);
                     elsif HS < 0.03 then
                        Bicycle (F);
                     end if;
                  end if;
               end;
            end loop;
            T := T + 7.0;
            K2 := K2 + 1;
         end loop;
         Ground_Details (AX, AZ, DX, DZ, L, Width);
      end Street;
      procedure Streets is new Road_Network.For_Segments_Near (Street);

      --  the walls by the streets: a tag here, posters there (not the same
      --  ones each time you play)
      procedure Wall (AX, AZ, BX, BZ, Bottom, Top : Float) is
         L  : constant Float := Sqrt ((BX - AX) ** 2 + (BZ - AZ) ** 2);
         MX : constant Float := (AX + BX) / 2.0;
         MZ : constant Float := (AZ + BZ) / 2.0;
         G  : constant Float := Terrain.Height (MX, MZ);
         H  : constant Float := Hash (Float'Rounding (MX * 3.0), Float'Rounding (MZ * 3.0), Session, 3.0);
      begin
         if L < 3.0 or else Top - Bottom < 4.0 or else Bottom > G + 1.0 or else not Mine (MX, MZ)
           or else H > 0.17
         then
            return;
         end if;
         declare
            Found : Boolean;
            RX, RZ, RH : Float;
            DX : constant Float := (BX - AX) / L;
            DZ : constant Float := (BZ - AZ) / L;
            NX : Float := -DZ;
            NZ : Float := DX;
         begin
            Road_Network.Nearest_Road (MX, MZ, Found, RX, RZ, RH);
            if not Found or else (RX - MX) ** 2 + (RZ - MZ) ** 2 > 22.0 ** 2 then
               return;
            end if;
            if NX * (RX - MX) + NZ * (RZ - MZ) < 0.0 then   --  the side facing the street
               NX := -NX;
               NZ := -NZ;
            end if;
            declare
               N    : constant Vec3 := (NX, 0.0, NZ);
               D    : constant Vec3 := (DX, 0.0, DZ);
               Base : constant Vec3 := (AX, Bottom, AZ);
               H2   : constant Float := Hash (MX, MZ, Session, 5.0);
            begin
               if H < 0.1 then
                  --  a tag, sprayed at arm's height
                  declare
                     W  : constant Float := Float'Min (L - 0.6, 1.4 + 2.4 * H2);
                     S0 : constant Float := 0.3 + (L - 0.6 - W) * Hash (MX, MZ, Session, 6.0);
                     Y0 : constant Float := 0.35 + 0.5 * H2;
                     Ht : constant Float := W * 0.42;
                     P0 : constant Vec3 := Base + S0 * D + Vec3'(0.0, Y0, 0.0) + 0.03 * N;
                  begin
                     Meshes.Quad_UV (P0, P0 + W * D, P0 + W * D + Vec3'(0.0, Ht, 0.0),
                                     P0 + Vec3'(0.0, Ht, 0.0), N, Mat_Tag, 50.0 * H2 + Session);
                  end;
               else
                  --  posters, two to four side by side, now and then one
                  --  pasted over another
                  declare
                     Count : constant Positive := 2 + Natural (Float'Floor (H2 * 2.99));
                     PW    : constant Float := 0.8;
                     Span  : constant Float := Float (Count) * (PW + 0.03);
                  begin
                     if Span < L - 0.4 then
                        for I in 0 .. Count - 1 loop
                           declare
                              S0 : constant Float := (L - Span) / 2.0 + Float (I) * (PW + 0.03);
                              Lift : constant Float := 0.06 * Hash (MX, MZ, Session, Float (I));
                              P0 : constant Vec3 := Base + S0 * D + Vec3'(0.0, 1.0 + Lift, 0.0)
                                + (0.035 + 0.005 * Float (I mod 2)) * N;
                           begin
                              Meshes.Quad_UV (P0, P0 + PW * D, P0 + PW * D + Vec3'(0.0, 1.15, 0.0),
                                              P0 + Vec3'(0.0, 1.15, 0.0), N, Mat_Poster,
                                              Float (I) * 3.0 + 100.0 * H2 + Session);
                           end;
                        end loop;
                     end if;
                  end;
               end if;
            end;
         end;
      end Wall;
      procedure Walls is new World.For_Walls_Near (Wall);
   begin
      Meshes.Start;
      Streets (Mid_X, Mid_Z, Cell_Size);
      Walls (Mid_X, Mid_Z, Cell_Size * 0.75);
      Meshes.Finish (C.Mesh);
   end Build_Cell;

   ---------------------------------------------------------------------------
   --  Newspapers in the wind
   ---------------------------------------------------------------------------

   type Sheet is record
      On       : Boolean := False;
      P, V     : Vec3 := (0.0, 0.0, 0.0);
      Yaw, Roll, Spin : Float := 0.0;
   end record;
   Sheets : array (1 .. 10) of Sheet;
   Sheet_Mesh : Meshes.Mesh;
   Float_Mesh : Meshes.Mesh;
   Float_Built : Boolean := False;
   Sheet_Built : Boolean := False;
   Wind_Time : Float := 0.0;

   procedure Update (Dt : Float; Focus_X, Focus_Z : Float) is
      --  the wind turns slowly and comes in gusts
      Dir  : constant Float := 0.8 * Sin (Wind_Time * 0.031) + 0.4 * Sin (Wind_Time * 0.11);
      Gust : constant Float := 1.0 + 0.8 * Float'Max (0.0, Sin (Wind_Time * 0.47) * Sin (Wind_Time * 0.13));
      Wind : constant Vec3 := (2.2 * Gust * Cos (Dir), 0.0, 2.2 * Gust * Sin (Dir));
   begin
      Begin_Session;
      Wind_Time := Wind_Time + Dt;
      for S of Sheets loop
         if not S.On or else (S.P.X - Focus_X) ** 2 + (S.P.Z - Focus_Z) ** 2 > 70.0 ** 2 then
            --  a new one somewhere on a street near you
            declare
               Found : Boolean;
               W, Pos : Natural;
            begin
               Road_Network.Pick_Segment (Focus_X, Focus_Z, 10.0, 55.0, Rnd, Rnd, Rnd, Found, W, Pos);
               if Found then
                  declare
                     A : constant Road_Network.Node := Road_Network.Point (W, Pos);
                     B : constant Road_Network.Node := Road_Network.Point (W, Pos + 1);
                     T : constant Float := Rnd;
                     X : constant Float := A.X + T * (B.X - A.X);
                     Z : constant Float := A.Z + T * (B.Z - A.Z);
                  begin
                     S := (On => True, P => (X, Terrain.Height (X, Z) + 0.02, Z),
                           V => (0.0, 0.0, 0.0), Yaw => 2.0 * Pi * Rnd, Roll => 0.0,
                           Spin => 0.0);
                  end;
               end if;
            end;
         else
            declare
               G : constant Float := Terrain.Height (S.P.X, S.P.Z) + 0.02;
            begin
               if S.P.Y <= G + 0.01 then
                  --  on the ground: pushed along by the gusts, flipping over
                  S.V := S.V + Dt * 2.5 * (Gust - 1.2) * Wind;
                  S.V.X := S.V.X * (1.0 - 2.0 * Dt);
                  S.V.Z := S.V.Z * (1.0 - 2.0 * Dt);
                  if Gust > 1.5 and then Rnd < Dt * 0.6 then   --  lifted
                     S.V.Y := 1.5 + 2.0 * Rnd;
                     S.Spin := 4.0 * (Rnd - 0.5);
                  end if;
                  S.Roll := S.Roll * (1.0 - 3.0 * Dt);
               else
                  --  in the air: drifting with the wind, fluttering down
                  S.V := S.V + Dt * (0.8 * (Wind - S.V) + Vec3'(0.0, -2.2, 0.0));
                  S.V.Y := Float'Max (S.V.Y, -1.2);
                  S.Roll := S.Roll + S.Spin * Dt;
               end if;
               S.P := S.P + Dt * S.V;
               if S.P.Y < G then
                  S.P.Y := G;
                  S.V.Y := 0.0;
               end if;
               if abs S.V.X + abs S.V.Z > 0.2 then
                  S.Yaw := S.Yaw + Dt * 1.5 * Sin (Wind_Time * 3.0 + S.P.X);
               end if;
            end;
         end if;
      end loop;
   end Update;

   ---------------------------------------------------------------------------

   procedure Draw (Model : GL.GLint; Cam : Vec3) is
      use Cell_Maps;
      CX0 : constant Integer := Integer (Float'Floor ((Cam.X - Reach) / Cell_Size));
      CX1 : constant Integer := Integer (Float'Floor ((Cam.X + Reach) / Cell_Size));
      CZ0 : constant Integer := Integer (Float'Floor ((Cam.Z - Reach) / Cell_Size));
      CZ1 : constant Integer := Integer (Float'Floor ((Cam.Z + Reach) / Cell_Size));
      Builds : Natural := 0;
   begin
      Begin_Session;
      --  let go of the cells far behind
      declare
         Gone : array (1 .. 64) of Cell_Key;
         N    : Natural := 0;
      begin
         for C in Cells.Iterate loop
            declare
               K  : constant Cell_Key := Key (C);
               MX : constant Float := (Float (K.CX) + 0.5) * Cell_Size;
               MZ : constant Float := (Float (K.CZ) + 0.5) * Cell_Size;
            begin
               if N < Gone'Last and then (MX - Cam.X) ** 2 + (MZ - Cam.Z) ** 2 > Let_Go ** 2 then
                  N := N + 1;
                  Gone (N) := K;
               end if;
            end;
         end loop;
         for I in 1 .. N loop
            declare
               C : Cell := Cells.Element (Gone (I));
            begin
               Meshes.Free (C.Mesh);
               Cells.Delete (Gone (I));
            end;
         end loop;
      end;
      --  build what is missing nearby, the nearest first, two a frame
      for Ring in 0 .. Integer'Max (CX1 - CX0, CZ1 - CZ0) loop
         exit when Builds >= 2;
         for CX in CX0 .. CX1 loop
            for CZ in CZ0 .. CZ1 loop
               declare
                  K  : constant Cell_Key := (CX, CZ);
                  MX : constant Float := (Float (CX) + 0.5) * Cell_Size;
                  MZ : constant Float := (Float (CZ) + 0.5) * Cell_Size;
                  D  : constant Float := Sqrt ((MX - Cam.X) ** 2 + (MZ - Cam.Z) ** 2);
               begin
                  if Builds < 2 and then Integer (D / Cell_Size) = Ring and then D < Reach
                    and then not Cells.Contains (K)
                  then
                     declare
                        New_Cell : Cell;
                     begin
                        Build_Cell (K, New_Cell);
                        Cells.Insert (K, New_Cell);
                        Builds := Builds + 1;
                     end;
                  end if;
               end;
            end loop;
         end loop;
      end loop;

      Shaders.Set (Model, Identity);
      for C in Cells.Iterate loop
         declare
            K  : constant Cell_Key := Key (C);
            MX : constant Float := (Float (K.CX) + 0.5) * Cell_Size;
            MZ : constant Float := (Float (K.CZ) + 0.5) * Cell_Size;
         begin
            if (MX - Cam.X) ** 2 + (MZ - Cam.Z) ** 2 < Reach ** 2 then
               Meshes.Draw (Element (C).Mesh);
            end if;
         end;
      end loop;

      --  what bobs in the air: a ball on a string
      if not Float_Built then
         Meshes.Start;
         declare
            R : constant Float := 0.23;
            function P (I, J : Integer) return Vec3 is
               Phi : constant Float := 2.0 * Pi * Float (I) / 14.0;
               Th  : constant Float := Pi * Float (J) / 8.0;
            begin
               return (R * Sin (Th) * Cos (Phi), 0.95 - R * 1.15 * Cos (Th), R * Sin (Th) * Sin (Phi));
            end P;
         begin
            for J in 0 .. 7 loop
               for I in 0 .. 13 loop
                  Face (P (I, J), P (I, J + 1), P (I + 1, J + 1), P (I + 1, J),
                        0.25 * (P (I, J) + P (I, J + 1) + P (I + 1, J + 1) + P (I + 1, J)) - Vec3'(0.0, 0.95, 0.0),
                        Mat_Rubber);
               end loop;
            end loop;
            Meshes.Box (-0.004, 0.004, 0.02, 0.69, -0.004, 0.004, Mat_Mouth);   --  the string
         end;
         Meshes.Finish (Float_Mesh);
         Float_Built := True;
      end if;
      for C in Cells.Iterate loop
         for F of Element (C).Floats loop
            if (F.X - Cam.X) ** 2 + (F.Z - Cam.Z) ** 2 < 140.0 ** 2 then
               Shaders.Set (Model, Translation (F + Vec3'(0.05 * Sin (Wind_Time * 0.7 + F.X),
                                                         0.06 * Sin (Wind_Time * 1.3 + F.Z), 0.0))
                            * Rotation_Z (0.05 * Sin (Wind_Time * 0.9)));
               Meshes.Draw (Float_Mesh);
            end if;
         end loop;
      end loop;

      --  the newspapers
      if not Sheet_Built then
         Meshes.Start;
         --  a sheet folded down the middle
         Meshes.Quad_UV ((-0.28, 0.0, -0.2), (0.0, 0.05, -0.2), (0.0, 0.05, 0.2), (-0.28, 0.0, 0.2),
                         (0.0, 1.0, 0.0), Mat_Paper, 0.0, 0.5, 1.0);
         Meshes.Quad_UV ((0.0, 0.05, -0.2), (0.28, 0.0, -0.2), (0.28, 0.0, 0.2), (0.0, 0.05, 0.2),
                         (0.0, 1.0, 0.0), Mat_Paper, 0.0, 0.5, 1.0);
         Meshes.Finish (Sheet_Mesh);
         Sheet_Built := True;
      end if;
      for S of Sheets loop
         if S.On and then (S.P.X - Cam.X) ** 2 + (S.P.Z - Cam.Z) ** 2 < 80.0 ** 2 then
            Shaders.Set (Model, Translation (S.P) * Rotation_Y (S.Yaw) * Rotation_Z (S.Roll));
            Meshes.Draw (Sheet_Mesh);
         end if;
      end loop;
   end Draw;

   procedure Collide (S : in out Car.State) is
      KX : constant Integer := Integer (Float'Floor (S.X / Cell_Size));
      KZ : constant Integer := Integer (Float'Floor (S.Z / Cell_Size));
      F  : constant Vec3 := Car.Forward (S);
   begin
      for DX in -1 .. 1 loop
         for DZ in -1 .. 1 loop
            declare
               C : constant Cell_Maps.Cursor := Cells.Find ((KX + DX, KZ + DZ));
            begin
               if Cell_Maps.Has_Element (C) then
                  for O of Cell_Maps.Element (C).Solids loop
                     for Along of Float_List'(-1.5, 0.0, 1.6) loop
                        declare
                           QX : constant Float := S.X + Along * F.X;
                           QZ : constant Float := S.Z + Along * F.Z;
                           EX : constant Float := QX - O.X;
                           EZ : constant Float := QZ - O.Z;
                           D  : constant Float := Sqrt (EX * EX + EZ * EZ);
                           R  : constant Float := O.R + 0.95;
                        begin
                           if D < R and then D > 0.001 then
                              S.X := S.X + EX / D * (R - D);
                              S.Z := S.Z + EZ / D * (R - D);
                              if (F.X * EX + F.Z * EZ) * S.Speed < 0.0 then
                                 S.Speed := S.Speed * 0.4;   --  ran into it
                              end if;
                              S.Bumped := True;
                              S.Hit_NX := EX / D;
                              S.Hit_NZ := EZ / D;
                           end if;
                        end;
                     end loop;
                  end loop;
               end if;
            end;
         end loop;
      end loop;
   end Collide;

end Street_Life;
