--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;

with Geo;
with Meshes;
with Shaders;
with Terrain;
with World;

package body Stravinsky is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;

   Pi : constant := Ada.Numerics.Pi;

   Mat_Paint : constant := 54.0;   --  glossy, in uCarColor
   Mat_Water : constant := 62.0;   --  bright and shiny: the jets
   Mat_Mural : constant := 73.0;   --  a painted wall, from a seed

   Centre : Vec3 := (0.0, 0.0, 0.0);
   Clock  : Float := 0.0;

   --  A part: its mesh, its colour, and how it moves (turning about a
   --  vertical axis through Pivot, or a wheel turning about Axis)
   type Motion is (Still, Turn_Y, Wheel);
   type Part is record
      Mesh   : Meshes.Mesh;
      Colour : Vec3;
      Move   : Motion := Still;
      Pivot  : Vec3 := (0.0, 0.0, 0.0);
      Speed  : Float := 0.0;
      Axis_Yaw : Float := 0.0;    --  for a wheel: which way its axle points
   end record;
   Parts : array (1 .. 24) of Part;
   Count : Natural := 0;

   type Jet is record
      From, V : Vec3;
   end record;
   Jets : array (1 .. 16) of Jet;
   Jet_Count : Natural := 0;
   Drop : Meshes.Mesh;

   Murals : Meshes.Mesh;
   Murals_Done : Boolean := False;
   Built  : Boolean := False;

   --  A turn by Angle about the unit axis A (column-major, like Math3D)
   function About (A : Vec3; Angle : Float) return Mat4 is
      C : constant Float := Cos (Angle);
      S : constant Float := Sin (Angle);
      T : constant Float := 1.0 - C;
      M : Mat4 := Identity;
      procedure Put (Row, Col : Natural; V : Float) is
      begin
         M (Col * 4 + Row) := V;
      end Put;
   begin
      Put (0, 0, T * A.X * A.X + C);       Put (0, 1, T * A.X * A.Y - S * A.Z); Put (0, 2, T * A.X * A.Z + S * A.Y);
      Put (1, 0, T * A.X * A.Y + S * A.Z); Put (1, 1, T * A.Y * A.Y + C);       Put (1, 2, T * A.Y * A.Z - S * A.X);
      Put (2, 0, T * A.X * A.Z - S * A.Y); Put (2, 1, T * A.Y * A.Z + S * A.X); Put (2, 2, T * A.Z * A.Z + C);
      return M;
   end About;

   ---------------------------------------------------------------------------
   --  Shapes

   procedure Face (A, B, C, D, N : Vec3; Mat : Float := Mat_Paint) is
   begin
      if Dot (Cross (B - A, D - A), N) >= 0.0 then
         Meshes.Quad (A, B, C, D, Mat);
      else
         Meshes.Quad (D, C, B, A, Mat);
      end if;
   end Face;

   procedure Blob (C : Vec3; RX, RY, RZ : Float; Segs : Positive := 14) is
      Rings : constant Positive := Segs / 2;
      function P (I, J : Integer) return Vec3 is
         Phi : constant Float := 2.0 * Pi * Float (I) / Float (Segs);
         Th  : constant Float := Pi * Float (J) / Float (Rings);
      begin
         return C + Vec3'(RX * Sin (Th) * Cos (Phi), -RY * Cos (Th), RZ * Sin (Th) * Sin (Phi));
      end P;
   begin
      for J in 0 .. Rings - 1 loop
         for I in 0 .. Segs - 1 loop
            Face (P (I, J), P (I, J + 1), P (I + 1, J + 1), P (I + 1, J),
                  0.25 * (P (I, J) + P (I, J + 1) + P (I + 1, J + 1) + P (I + 1, J)) - C);
         end loop;
      end loop;
   end Blob;

   procedure Tube (P0, P1 : Vec3; R : Float; Segs : Positive := 10) is
      D : constant Vec3 := Normalize (P1 - P0);
      A : constant Vec3 := Normalize (Cross (D, (if abs D.Y < 0.9 then Vec3'(0.0, 1.0, 0.0) else Vec3'(1.0, 0.0, 0.0))));
      B : constant Vec3 := Cross (D, A);
      function Rim (I : Integer) return Vec3 is
         T : constant Float := 2.0 * Pi * Float (I) / Float (Segs);
      begin
         return R * (Cos (T) * A + Sin (T) * B);
      end Rim;
   begin
      for I in 0 .. Segs - 1 loop
         Face (P0 + Rim (I), P1 + Rim (I), P1 + Rim (I + 1), P0 + Rim (I + 1), Rim (I) + Rim (I + 1));
      end loop;
   end Tube;

   --  A flat disc (two faces) standing in the plane of U and V
   procedure Disc (C, U, V : Vec3; R : Float; Segs : Positive := 20) is
      N : constant Vec3 := Cross (U, V);
   begin
      for I in 0 .. Segs - 1 loop
         declare
            A0 : constant Float := 2.0 * Pi * Float (I) / Float (Segs);
            A1 : constant Float := 2.0 * Pi * Float (I + 1) / Float (Segs);
            P0 : constant Vec3 := C + R * (Cos (A0) * U + Sin (A0) * V);
            P1 : constant Vec3 := C + R * (Cos (A1) * U + Sin (A1) * V);
         begin
            Face (C, P0, P1, P1, N);
            Face (C, P1, P0, P0, (-1.0) * N);
         end;
      end loop;
   end Disc;

   procedure Begin_Part is
   begin
      Meshes.Start;
   end Begin_Part;

   procedure End_Part (Colour : Vec3; Move : Motion := Still; Pivot : Vec3 := (0.0, 0.0, 0.0);
                       Speed : Float := 0.0; Axis_Yaw : Float := 0.0) is
   begin
      Count := Count + 1;
      Meshes.Finish (Parts (Count).Mesh);
      Parts (Count).Colour := Colour;
      Parts (Count).Move := Move;
      Parts (Count).Pivot := Pivot;
      Parts (Count).Speed := Speed;
      Parts (Count).Axis_Yaw := Axis_Yaw;
   end End_Part;

   procedure Add_Jet (From, V : Vec3) is
   begin
      if Jet_Count < Jets'Last then
         Jet_Count := Jet_Count + 1;
         Jets (Jet_Count) := (From, V);
      end if;
   end Add_Jet;

   function At_C (X, Y, Z : Float) return Vec3 is (Centre + Vec3'(X, Y, Z));

   Red    : constant Vec3 := (0.88, 0.12, 0.12);
   Yellow : constant Vec3 := (0.98, 0.8, 0.1);
   Blue   : constant Vec3 := (0.12, 0.35, 0.85);
   Green  : constant Vec3 := (0.15, 0.62, 0.3);
   Pink   : constant Vec3 := (0.95, 0.4, 0.65);
   Black  : constant Vec3 := (0.06, 0.06, 0.07);
   Orange : constant Vec3 := (0.98, 0.5, 0.1);

   procedure Create is
      X, Z : Long_Float;
   begin
      Geo.To_Local (48.859472, 2.351476, X, Z);
      Centre := (Float (X), Terrain.Height (Float (X), Float (Z)), Float (Z));

      --  a big bird, wings spread, on a stem: body, wings and tail in colours
      Begin_Part;
      Tube (At_C (-5.0, 0.0, -3.0), At_C (-5.0, 2.2, -3.0), 0.18);
      Blob (At_C (-5.0, 3.2, -3.0), 1.4, 0.9, 0.7);
      Blob (At_C (-6.2, 4.1, -3.0), 0.55, 0.55, 0.5);                       --  head
      End_Part (Red);
      Begin_Part;
      Face (At_C (-5.0, 3.4, -3.3), At_C (-3.0, 5.6, -3.6), At_C (-1.8, 4.6, -3.4), At_C (-4.2, 3.0, -3.2),
            (0.0, 0.0, -1.0));
      Face (At_C (-5.0, 3.4, -2.7), At_C (-3.0, 5.6, -2.4), At_C (-1.8, 4.6, -2.6), At_C (-4.2, 3.0, -2.8),
            (0.0, 0.0, 1.0));
      End_Part (Yellow);
      Begin_Part;
      Face (At_C (-3.8, 3.0, -3.0), At_C (-2.2, 2.4, -3.3), At_C (-2.0, 3.6, -3.0), At_C (-2.2, 2.4, -2.7),
            (1.0, 0.3, 0.0));
      Blob (At_C (-6.75, 4.1, -3.0), 0.35, 0.12, 0.18, 10);                 --  beak
      End_Part (Blue);

      --  big red lips, on a black stem, squirting
      Begin_Part;
      Blob (At_C (4.5, 2.25, -4.0), 1.3, 0.38, 0.55);
      Blob (At_C (4.5, 1.65, -4.0), 1.15, 0.38, 0.5);
      End_Part (Red);
      Begin_Part;
      Tube (At_C (4.5, 0.0, -4.0), At_C (4.5, 1.4, -4.0), 0.12);
      End_Part (Black);
      Add_Jet (At_C (4.5, 1.95, -3.45), (0.0, 2.2, 2.6));

      --  a heart, turning slowly
      Begin_Part;
      Blob (At_C (0.0, 2.6, 5.0) + Vec3'(-0.55, 0.0, 0.0), 0.75, 0.75, 0.45);
      Blob (At_C (0.0, 2.6, 5.0) + Vec3'(0.55, 0.0, 0.0), 0.75, 0.75, 0.45);
      Face (At_C (-1.25, 2.5, 5.0), At_C (1.25, 2.5, 5.0), At_C (0.0, 0.9, 5.0), At_C (0.0, 0.9, 5.0), (0.0, 0.0, -1.0));
      Face (At_C (-1.25, 2.5, 5.0), At_C (1.25, 2.5, 5.0), At_C (0.0, 0.9, 5.0), At_C (0.0, 0.9, 5.0), (0.0, 0.0, 1.0));
      End_Part (Red, Turn_Y, At_C (0.0, 0.0, 5.0), 0.35);
      Begin_Part;
      Tube (At_C (0.0, 0.0, 5.0), At_C (0.0, 0.95, 5.0), 0.1);
      End_Part (Black);

      --  a snake, coiled and striped: alternate rings in two colours
      for Colour_Pass in 0 .. 1 loop
         Begin_Part;
         for K in 0 .. 23 loop
            if K mod 2 = Colour_Pass then
               declare
                  T0 : constant Float := Float (K) / 24.0;
                  T1 : constant Float := Float (K + 1) / 24.0;
                  function S (T : Float) return Vec3 is
                    (At_C (6.0 + 1.3 * Cos (6.0 * T), 0.35 + 2.6 * T, 3.5 + 1.3 * Sin (6.0 * T)));
               begin
                  Tube (S (T0), S (T1), 0.32 - 0.12 * T0, 12);
               end;
            end if;
         end loop;
         if Colour_Pass = 1 then
            Blob (At_C (6.0 + 1.3 * Cos (6.0), 3.15, 3.5 + 1.3 * Sin (6.0)), 0.42, 0.3, 0.3);
         end if;
         End_Part ((if Colour_Pass = 0 then Green else Yellow));
      end loop;
      Add_Jet (At_C (6.0 + 1.3 * Cos (6.0), 3.15, 3.5 + 1.3 * Sin (6.0)), (-1.6, 1.4, 0.8));

      --  a spiral, rising, turning
      Begin_Part;
      for K in 0 .. 29 loop
         declare
            T0 : constant Float := Float (K) / 30.0;
            T1 : constant Float := Float (K + 1) / 30.0;
            function S (T : Float) return Vec3 is
              (At_C (-6.5 + (1.5 - T) * Cos (12.0 * T), 0.3 + 4.0 * T, 4.0 + (1.5 - T) * Sin (12.0 * T)));
         begin
            Tube (S (T0), S (T1), 0.14, 8);
         end;
      end loop;
      End_Part (Blue, Turn_Y, At_C (-6.5, 0.0, 4.0), -0.6);

      --  a sun: a disc with rays, on a pole, turning
      Begin_Part;
      Disc (At_C (1.0, 4.4, -7.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), 0.9);
      for K in 0 .. 11 loop
         declare
            A : constant Float := 2.0 * Pi * Float (K) / 12.0;
         begin
            Face (At_C (1.0 + 0.85 * Cos (A - 0.15), 4.4 + 0.85 * Sin (A - 0.15), -7.0),
                  At_C (1.0 + 1.6 * Cos (A), 4.4 + 1.6 * Sin (A), -7.0),
                  At_C (1.0 + 1.6 * Cos (A), 4.4 + 1.6 * Sin (A), -7.0),
                  At_C (1.0 + 0.85 * Cos (A + 0.15), 4.4 + 0.85 * Sin (A + 0.15), -7.0), (0.0, 0.0, -1.0));
            Face (At_C (1.0 + 0.85 * Cos (A - 0.15), 4.4 + 0.85 * Sin (A - 0.15), -7.0),
                  At_C (1.0 + 1.6 * Cos (A), 4.4 + 1.6 * Sin (A), -7.0),
                  At_C (1.0 + 1.6 * Cos (A), 4.4 + 1.6 * Sin (A), -7.0),
                  At_C (1.0 + 0.85 * Cos (A + 0.15), 4.4 + 0.85 * Sin (A + 0.15), -7.0), (0.0, 0.0, 1.0));
         end;
      end loop;
      End_Part (Orange, Turn_Y, At_C (1.0, 0.0, -7.0), 0.25);
      Begin_Part;
      Tube (At_C (1.0, 0.0, -7.0), At_C (1.0, 3.5, -7.0), 0.1);
      End_Part (Black);
      Begin_Part;
      Blob (At_C (1.0, 4.4, -7.0), 0.3, 0.3, 0.12);                          --  the middle
      End_Part (Pink, Turn_Y, At_C (1.0, 0.0, -7.0), 0.25);

      --  three black machines: a frame on legs and a wheel that turns
      for M in 0 .. 2 loop
         declare
            MX : constant Float := (case M is when 0 => -1.5, when 1 => 8.0, when others => -8.5);
            MZ : constant Float := (case M is when 0 => -1.0, when 1 => -2.5, when others => -2.0);
            Yaw : constant Float := 0.9 * Float (M);
            Ax : constant Vec3 := (Cos (Yaw), 0.0, Sin (Yaw));
            C  : constant Vec3 := At_C (MX, 2.2, MZ);
         begin
            Begin_Part;
            for L in 0 .. 2 loop
               declare
                  A : constant Float := 2.0 * Pi * Float (L) / 3.0;
               begin
                  Tube (At_C (MX + 1.0 * Cos (A), 0.0, MZ + 1.0 * Sin (A)), C - 0.5 * Ax, 0.07, 6);
               end;
            end loop;
            Tube (C - 0.5 * Ax, C + 0.3 * Ax, 0.06, 6);                       --  the axle
            End_Part (Black);
            Begin_Part;
            declare
               U : constant Vec3 := (0.0, 1.0, 0.0);
               V : constant Vec3 := Cross (Ax, U);
            begin
               for K in 0 .. 15 loop
                  declare
                     A0 : constant Float := 2.0 * Pi * Float (K) / 16.0;
                     A1 : constant Float := 2.0 * Pi * Float (K + 1) / 16.0;
                  begin
                     Tube (C + 1.1 * (Cos (A0) * U + Sin (A0) * V), C + 1.1 * (Cos (A1) * U + Sin (A1) * V), 0.07, 6);
                     if K mod 4 = 0 then   --  spokes, and a cup on each
                        Tube (C, C + 1.1 * (Cos (A0) * U + Sin (A0) * V), 0.05, 6);
                        Blob (C + 1.2 * (Cos (A0) * U + Sin (A0) * V), 0.16, 0.16, 0.16, 8);
                     end if;
                  end;
               end loop;
            end;
            End_Part (Black, Wheel, C, 0.8 + 0.4 * Float (M), Yaw);
            Add_Jet (C + Vec3'(0.0, 1.2, 0.0), (0.6 * Cos (Yaw + 1.6), 3.4, 0.6 * Sin (Yaw + 1.6)));
         end;
      end loop;

      --  a black arm that swings round, spraying as it goes
      Begin_Part;
      Tube (At_C (3.5, 0.0, 1.5), At_C (3.5, 2.8, 1.5), 0.09, 8);
      Tube (At_C (3.5, 2.8, 1.5), At_C (5.7, 3.1, 1.5), 0.07, 8);
      Blob (At_C (5.8, 3.1, 1.5), 0.2, 0.2, 0.2, 8);
      End_Part (Black, Turn_Y, At_C (3.5, 0.0, 1.5), 0.5);

      --  more jets from the water
      for K in 0 .. 4 loop
         declare
            A : constant Float := 2.0 * Pi * Float (K) / 5.0 + 0.3;
         begin
            Add_Jet (At_C (9.5 * Cos (A), 0.05, 9.5 * Sin (A)), (-1.2 * Cos (A), 4.5, -1.2 * Sin (A)));
         end;
      end loop;

      Meshes.Start;
      Meshes.Box (-0.05, 0.05, -0.05, 0.05, -0.05, 0.05, Mat_Water);
      Meshes.Finish (Drop);
      Built := True;
   end Create;

   procedure Update (Dt : Float) is
   begin
      Clock := Clock + Dt;
   end Update;

   ---------------------------------------------------------------------------
   --  Murals on the biggest walls that face the pool

   procedure Find_Murals is
      type Wall is record
         A, B : Vec3;
         Bottom, Top, Area : Float;
         N : Vec3;
      end record;
      Best : array (1 .. 2) of Wall := (others => (A => (0.0, 0.0, 0.0), B => (0.0, 0.0, 0.0), N => (0.0, 0.0, 0.0),
                                                   Bottom => 0.0, Top => 0.0, Area => 0.0));
      Seen : Natural := 0;
      procedure Visit (AX, AZ, BX, BZ, Bottom, Top : Float) is
         L : constant Float := Sqrt ((BX - AX) ** 2 + (BZ - AZ) ** 2);
         M : constant Vec3 := (0.5 * (AX + BX), 0.0, 0.5 * (AZ + BZ));
         D : constant Float := Sqrt ((M.X - Centre.X) ** 2 + (M.Z - Centre.Z) ** 2);
         N0 : Vec3;
      begin
         Seen := Seen + 1;
         if L < 9.0 or else Top - Bottom < 12.0 or else D < 12.0 or else D > 70.0 then
            return;
         end if;
         N0 := Normalize (Vec3'(-(BZ - AZ), 0.0, BX - AX));
         if Dot (N0, Centre - M) < 0.0 then
            N0 := (-1.0) * N0;
         end if;
         --  facing the pool, more or less
         if Dot (N0, Normalize (Vec3'(Centre.X - M.X, 0.0, Centre.Z - M.Z))) < 0.7 then
            return;
         end if;
         declare
            W : constant Wall := ((AX, 0.0, AZ), (BX, 0.0, BZ), Bottom, Top,
                                  L * Float'Min (18.0, Top - Bottom), N0);
         begin
            if W.Area > Best (1).Area then
               --  not two on the same side
               if Best (1).Area > 0.0 and then Dot (Best (1).N, W.N) < 0.8 then
                  Best (2) := Best (1);
               end if;
               Best (1) := W;
            elsif W.Area > Best (2).Area and then Dot (Best (1).N, W.N) < 0.8 then
               Best (2) := W;
            end if;
         end;
      end Visit;
      procedure Walls is new World.For_Walls_Near (Visit);
   begin
      Walls (Centre.X, Centre.Z, 80.0);
      if Seen = 0 then
         return;   --  the tiles are not there yet
      end if;
      Meshes.Start;
      for K in Best'Range loop
         if Best (K).Area > 0.0 then
            declare
               W  : Wall renames Best (K);
               D  : constant Vec3 := W.B - W.A;
               P0 : constant Vec3 := W.A + 0.08 * D + 0.06 * W.N + Vec3'(0.0, W.Bottom + 2.5, 0.0);
               P1 : constant Vec3 := W.A + 0.92 * D + 0.06 * W.N + Vec3'(0.0, W.Bottom + 2.5, 0.0);
               H  : constant Float := Float'Min (16.0, W.Top - W.Bottom - 4.0);
               --  the seed: a pattern (shapes, circles and lines) and colours
               Seed : constant Float := (if K = 1 then 9.0 + 16.0 * 4.0 + 128.0 * 7.0
                                         else 2.0 + 16.0 * 0.0 + 128.0 * 31.0);
            begin
               Meshes.Quad_UV (P0, P1, P1 + Vec3'(0.0, H, 0.0), P0 + Vec3'(0.0, H, 0.0), W.N, Mat_Mural, Seed);
            end;
         end if;
      end loop;
      Meshes.Finish (Murals);
      Murals_Done := True;
   end Find_Murals;

   ---------------------------------------------------------------------------

   procedure Draw (Model, Paint : GL.GLint; Cam : Vec3) is
   begin
      if not Built or else (Cam.X - Centre.X) ** 2 + (Cam.Z - Centre.Z) ** 2 > 450.0 ** 2 then
         return;
      end if;
      if not Murals_Done then
         Find_Murals;
      end if;
      if Murals_Done then
         Shaders.Set (Model, Identity);
         Meshes.Draw (Murals);
      end if;
      for I in 1 .. Count loop
         declare
            P : Part renames Parts (I);
         begin
            Shaders.Set (Paint, P.Colour);
            case P.Move is
               when Still =>
                  Shaders.Set (Model, Identity);
               when Turn_Y =>
                  Shaders.Set (Model, Translation (P.Pivot) * Rotation_Y (P.Speed * Clock)
                                      * Translation ((-1.0) * P.Pivot));
               when Wheel =>
                  --  about a horizontal axle pointing along Axis_Yaw
                  Shaders.Set (Model, Translation (P.Pivot)
                                      * About ((Cos (P.Axis_Yaw), 0.0, Sin (P.Axis_Yaw)), P.Speed * Clock)
                                      * Translation ((-1.0) * P.Pivot));
            end case;
            Meshes.Draw (P.Mesh);
         end;
      end loop;
      --  the water: drops along each jet's arc
      for J in 1 .. Jet_Count loop
         declare
            T_Fly : constant Float := 2.0 * Jets (J).V.Y / 9.81;
         begin
            for K in 0 .. 17 loop
               declare
                  F : constant Float := Float (K) / 18.0 + Clock * 0.9 / T_Fly;
                  T : constant Float := T_Fly * (F - Float'Floor (F));
                  Q : constant Vec3 := Jets (J).From + T * Jets (J).V + Vec3'(0.0, -4.905 * T * T, 0.0);
               begin
                  if Q.Y > Centre.Y - 0.05 then
                     Shaders.Set (Model, Translation (Q));
                     Meshes.Draw (Drop);
                  end if;
               end;
            end loop;
         end;
      end loop;
   end Draw;

end Stravinsky;
