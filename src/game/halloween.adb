--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Numerics.Float_Random;

with Geo;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Meshes;
with Terrain;
with Road_Network;
with Shaders;
with Sound;
with World;

package body Halloween is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;

   Mat_Pumpkin : constant := 40.0;
   Mat_Face    : constant := 41.0;   --  the carved face, glowing at night
   Mat_Ghost   : constant := 42.0;
   Mat_Stem    : constant := 13.0;
   Mat_Black   : constant := 17.0;

   Pumpkin_Mesh, Ghost_Mesh : Meshes.Mesh;

   Gen : Ada.Numerics.Float_Random.Generator;
   function Rnd return Float is (Ada.Numerics.Float_Random.Random (Gen));
   function Sym return Float is (2.0 * Rnd - 1.0);

   Active : Boolean := False;
   Dark   : Boolean := False;
   Clock  : Float := 0.0;

   --  Pumpkins: by some of the street lamps near you
   Max_Pumpkins : constant := 40;
   type Pumpkin is record
      Pos : Vec3;
      Yaw : Float;
      Size : Float;
   end record;
   Pumpkins : array (1 .. Max_Pumpkins) of Pumpkin;
   Pumpkin_Count : Natural := 0;
   Look_Again    : Float := 0.0;

   --  A stable random number for a place
   function Hash (X, Z : Float) return Float is
      V : constant Float := Sin (X * 12.9898 + Z * 78.233) * 43_758.547;
   begin
      return V - Float'Floor (V);
   end Hash;

   --  Ghosts
   type Ghost is record
      Alive  : Boolean := False;
      Pos    : Vec3 := (0.0, 0.0, 0.0);
      Vel    : Vec3 := (0.0, 0.0, 0.0);
      Phase  : Float := 0.0;
      Swoop  : Float := 0.0;    --  > 0: diving at the car
      Wooed  : Boolean := False;
   end record;
   --  1 .. 4 roam the streets at Halloween; the rest haunt the cemeteries
   --  of Montparnasse and Père-Lachaise every night of the year
   Roamers  : constant := 4;
   Haunters : constant := 21;
   Ghosts : array (1 .. Roamers + Haunters) of Ghost;

   --  The cemeteries (outlines from data/cemeteries.txt), with their
   --  graves built when you come near
   Max_Corners : constant := 200;
   type Corner_Array is array (1 .. Max_Corners) of Vec3;
   type Cemetery is record
      Corners  : Corner_Array;
      N        : Natural := 0;
      Lo, Hi   : Vec3 := (0.0, 0.0, 0.0);
      Graves   : Meshes.Mesh;
      Built    : Boolean := False;
      Pere_Lachaise : Boolean := False;   --  full of family chapels
   end record;
   Cemeteries : array (1 .. 6) of Cemetery;
   Cemetery_Count : Natural := 0;

   function Inside (C : Cemetery; X, Z : Float) return Boolean is
      In_It : Boolean := False;
      J     : Natural := C.N;
   begin
      for I in 1 .. C.N loop
         if (C.Corners (I).Z > Z) /= (C.Corners (J).Z > Z)
           and then X < C.Corners (I).X + (Z - C.Corners (I).Z)
             * (C.Corners (J).X - C.Corners (I).X) / (C.Corners (J).Z - C.Corners (I).Z)
         then
            In_It := not In_It;
         end if;
         J := I;
      end loop;
      return In_It;
   end Inside;

   function Distance (C : Cemetery; P : Vec3) return Float is
      DX : constant Float := Float'Max (0.0, Float'Max (C.Lo.X - P.X, P.X - C.Hi.X));
      DZ : constant Float := Float'Max (0.0, Float'Max (C.Lo.Z - P.Z, P.Z - C.Hi.Z));
   begin
      return Sqrt (DX * DX + DZ * DZ);
   end Distance;

   function Home_Of (I : Positive) return Natural is
     (if I <= Roamers or else Cemetery_Count = 0 then 0
      else 1 + (I - Roamers - 1) mod Cemetery_Count);

   procedure Load_Cemeteries is
      use Ada.Text_IO;
      F : File_Type;
   begin
      Open (F, In_File, "data/cemeteries.txt");
      while not End_Of_File (F) loop
         declare
            Line : constant String := Get_Line (F);
         begin
            if Line'Length >= 8 and then Line (Line'First .. Line'First + 7) = "cemetery" then
               if Cemetery_Count < Cemeteries'Last then
                  Cemetery_Count := Cemetery_Count + 1;
                  Cemeteries (Cemetery_Count).Pere_Lachaise :=
                    Ada.Strings.Fixed.Index (Line, "Lachaise") > 0;
               end if;
            elsif Line'Length > 0 and then Line (Line'First) /= '#' and then Cemetery_Count > 0 then
               declare
                  Sp : constant Natural := Ada.Strings.Fixed.Index (Line, " ");
                  X, Z : Long_Float;
                  C : Cemetery renames Cemeteries (Cemetery_Count);
               begin
                  Geo.To_Local (Long_Float'Value (Line (Line'First .. Sp - 1)),
                                Long_Float'Value (Line (Sp + 1 .. Line'Last)), X, Z);
                  if C.N < Max_Corners then
                     C.N := C.N + 1;
                     C.Corners (C.N) := (Float (X), 0.0, Float (Z));
                     if C.N = 1 then
                        C.Lo := C.Corners (1);
                        C.Hi := C.Corners (1);
                     end if;
                     C.Lo := (Float'Min (C.Lo.X, Float (X)), 0.0, Float'Min (C.Lo.Z, Float (Z)));
                     C.Hi := (Float'Max (C.Hi.X, Float (X)), 0.0, Float'Max (C.Hi.Z, Float (Z)));
                  end if;
               end;
            end if;
         end;
      end loop;
      Close (F);
   exception
      when others =>
         if Is_Open (F) then
            Close (F);
         end if;
   end Load_Cemeteries;

   --  Rows of graves: headstones, crosses, flat slabs and family chapels,
   --  with paths between the blocks
   procedure Build_Graves (C : in out Cemetery) is
      use Meshes;
      Mat_Stone : constant := 2.0;    --  grey stone (not floodlit)
      Mat_Dark  : constant := 17.0;   --  black granite
      X : Float := C.Lo.X + 1.5;
      Col : Natural := 0;
   begin
      Start;
      while X < C.Hi.X loop
         Col := Col + 1;
         declare
            Z   : Float := C.Lo.Z + 2.0;
            Row : Natural := 0;
         begin
            while Z < C.Hi.Z loop
               Row := Row + 1;
               declare
                  H : constant Float := Hash (X, Z);
                  K : constant Float := Hash (Z + 7.0, X - 3.0);
                  M : constant Float := (if K < 0.2 then Mat_Dark else Mat_Stone);
                  G : constant Float := Terrain.Height (X, Z);   --  the hills
               begin
                  if Col mod 9 /= 0 and then Row mod 7 /= 0 and then H < 0.7
                    and then Inside (C, X, Z)
                  then
                     if K > (if C.Pere_Lachaise then 0.72 else 0.93) then
                        --  a family chapel with a pointed roof and a door
                        Box (X - 0.9, X + 0.9, G + 0.0, G + 2.6, Z - 1.3, Z + 1.3, Mat_Stone);
                        Box (X - 0.95, X + 0.95, G + 2.6, G + 3.5, Z - 1.35, Z + 1.35, Mat_Stone,
                             Top_Inset_X => 0.9);
                        Box (X - 0.4, X + 0.4, G + 0.0, G + 1.9, Z - 1.33, Z - 1.29, Mat_Dark);
                     else
                        --  a flat slab, and a headstone or a cross at its head
                        Box (X - 0.45, X + 0.45, G + 0.0, G + 0.25, Z - 0.9, Z + 1.0, M);
                        if H < 0.5 then
                           Box (X - 0.4, X + 0.4, G + 0.0, G + 0.8 + 0.4 * K, Z - 1.05, Z - 0.88, M,
                                Top_Inset_X => 0.05);
                        else
                           Box (X - 0.06, X + 0.06, G + 0.0, G + 1.3, Z - 1.0, Z - 0.9, Mat_Stone);
                           Box (X - 0.3, X + 0.3, G + 0.85, G + 0.97, Z - 1.0, Z - 0.9, Mat_Stone);
                        end if;
                     end if;
                  end if;
               end;
               Z := Z + 4.4;
            end loop;
         end;
         X := X + 3.2;
      end loop;
      Finish (C.Graves);
      C.Built := True;
   end Build_Graves;

   procedure Create_Mesh is
      use Meshes;
   begin
      --  a pumpkin: a squashed ball of boxes with ribs, a stem and a face
      --  on the front (-Z)
      Start;
      declare
         Segs  : constant := 16;
         Rings : constant := 8;
         --  a squashed ball with eight ribs
         function P (I, J : Integer) return Vec3 is
            Phi   : constant Float := 2.0 * Ada.Numerics.Pi * Float (I) / Float (Segs);
            Theta : constant Float := Ada.Numerics.Pi * Float (J) / Float (Rings);
            R     : constant Float := 0.27 * Sin (Theta) * (1.0 + 0.07 * Cos (8.0 * Phi));
         begin
            return (R * Cos (Phi), 0.21 - 0.2 * Cos (Theta), R * Sin (Phi));
         end P;
      begin
         for J in 0 .. Rings - 1 loop
            for I in 0 .. Segs - 1 loop
               --  wound so that the faces point outwards
               Quad (P (I, J), P (I, J + 1), P (I + 1, J + 1), P (I + 1, J), Mat_Pumpkin);
            end loop;
         end loop;
      end;
      Box (-0.03, 0.03, 0.4, 0.5, -0.03, 0.03, Mat_Stem);
      Box (-0.15, -0.06, 0.24, 0.32, -0.29, -0.27, Mat_Face);      --  eyes
      Box (0.06, 0.15, 0.24, 0.32, -0.29, -0.27, Mat_Face);
      Box (-0.025, 0.025, 0.18, 0.23, -0.29, -0.27, Mat_Face);     --  nose
      Box (-0.16, 0.16, 0.09, 0.14, -0.28, -0.26, Mat_Face);       --  grin
      Box (-0.11, -0.05, 0.14, 0.17, -0.29, -0.27, Mat_Face);
      Box (0.05, 0.11, 0.14, 0.17, -0.29, -0.27, Mat_Face);
      Finish (Pumpkin_Mesh);

      --  a ghost under a sheet: round head, wide hem, two dark eyes and
      --  an open mouth (front is -Z)
      Start;
      Box (-0.3, 0.3, 1.0, 1.45, -0.28, 0.28, Mat_Ghost,
           Top_Inset_X => 0.12, Top_Inset_Front => 0.1, Top_Inset_Back => 0.1);
      Box (-0.42, 0.42, 0.25, 1.0, -0.38, 0.38, Mat_Ghost,
           Top_Inset_X => 0.12, Top_Inset_Front => 0.1, Top_Inset_Back => 0.1);
      for I in 0 .. 3 loop                                            --  the hem
         declare
            X : constant Float := -0.42 + 0.21 * Float (I);
         begin
            Box (X, X + 0.2, (if I mod 2 = 0 then 0.0 else 0.1), 0.26, -0.38, 0.38, Mat_Ghost);
         end;
      end loop;
      Box (-0.17, -0.06, 1.12, 1.27, -0.30, -0.27, Mat_Black);       --  eyes
      Box (0.06, 0.17, 1.12, 1.27, -0.30, -0.27, Mat_Black);
      Box (-0.06, 0.06, 0.9, 1.04, -0.37, -0.34, Mat_Black);         --  "ooo"
      Box (-0.5, -0.4, 0.6, 0.85, -0.1, 0.1, Mat_Ghost);              --  arms
      Box (0.4, 0.5, 0.6, 0.85, -0.1, 0.1, Mat_Ghost);
      Finish (Ghost_Mesh);
      if Ada.Environment_Variables.Exists ("PARIS_FREEZE") then
         Ada.Numerics.Float_Random.Reset (Gen, 7);   --  the same ghosts every run (testing)
      else
         Ada.Numerics.Float_Random.Reset (Gen);
      end if;
      Load_Cemeteries;
   end Create_Mesh;

   procedure Spawn_Ghost (G : in out Ghost; Near : Vec3) is
      A : constant Float := 2.0 * Ada.Numerics.Pi * Rnd;
      D : constant Float := 30.0 + 50.0 * Rnd;
   begin
      G := (Alive => True,
            Pos   => (Near.X + D * Cos (A),
                      2.0 + 2.0 * Rnd + Terrain.Height (Near.X + D * Cos (A), Near.Z + D * Sin (A)),
                      Near.Z + D * Sin (A)),
            Vel   => (1.5 * Sym, 0.0, 1.5 * Sym),
            Phase => 6.3 * Rnd, Swoop => 0.0, Wooed => False);
   end Spawn_Ghost;

   procedure Ghost_Here (Where : Vec3) is
   begin
      Spawn_Ghost (Ghosts (1), Where);
      Ghosts (1).Pos := Where;
   end Ghost_Here;

   procedure Update (Dt : Float; On : Boolean; Night : Float;
                     Listener, Car_Pos : Vec3; Listener_Heading : Float) is
   begin
      Active := On;
      Dark := Night > 0.5;
      for C of Cemeteries (1 .. Cemetery_Count) loop
         if not C.Built and then Distance (C, Listener) < 900.0 then
            Build_Graves (C);
         elsif C.Built and then Distance (C, Listener) > 1400.0 then
            Meshes.Free (C.Graves);
            C.Built := False;
         end if;
      end loop;
      Clock := Clock + Dt;
      if not On then
         Pumpkin_Count := 0;
      end if;

      --  a pumpkin at about one lamp in three
      Look_Again := Look_Again - Dt;
      if On and then Look_Again <= 0.0 then
         Look_Again := 0.5;
         declare
            Lights : World.Light_Data;
            N      : Natural;
         begin
            World.Nearest_Lights (Listener.X, Listener.Z, Lights, N);
            Pumpkin_Count := 0;
            for I in 0 .. N - 1 loop
               declare
                  X : constant Float := Lights (4 * I);
                  Z : constant Float := Lights (4 * I + 2);
                  H : constant Float := Hash (X, Z);
               begin
                  if H < 0.35 and then Pumpkin_Count < Max_Pumpkins then
                     declare
                        Found  : Boolean;
                        RX, RZ, RH : Float;
                        PX : constant Float := X + 0.45 * Cos (H * 40.0);
                        PZ : constant Float := Z + 0.45 * Sin (H * 40.0);
                     begin
                        Road_Network.Nearest_Road (PX, PZ, Found, RX, RZ, RH);
                        Pumpkin_Count := Pumpkin_Count + 1;
                        Pumpkins (Pumpkin_Count) :=
                          (Pos  => (PX, 0.14 + Terrain.Height (PX, PZ), PZ),
                           --  the face (-Z) towards the street, a little askew
                           Yaw  => (if Found and then abs (RX - PX) + abs (RZ - PZ) > 0.1
                                    then -Arctan (RX - PX, -(RZ - PZ)) + 0.5 * (H - 0.17)
                                    else H * 60.0),
                           Size => 0.9 + 0.8 * Hash (X + 17.0, Z - 3.0));
                     end;
                  end if;
               end;
            end loop;
         end;
      end if;

      --  ghosts, after dark
      for I in Ghosts'Range loop
         declare
            G    : Ghost renames Ghosts (I);
            Home : constant Natural := Home_Of (I);
            Near_Home : constant Boolean :=
              Home > 0 and then Distance (Cemeteries (Home), Listener) < 500.0;
         begin
         if not Dark or else (Home = 0 and then not On) or else (Home > 0 and then not Near_Home) then
            G.Alive := False;
         elsif not G.Alive then
            if Home = 0 and then Rnd < Dt / 4.0 then
               Spawn_Ghost (G, Listener);
            elsif Home > 0 then
               --  rising from among the graves
               declare
                  C : Cemetery renames Cemeteries (Home);
                  P : Vec3;
               begin
                  for Try in 1 .. 20 loop
                     P := (C.Lo.X + (C.Hi.X - C.Lo.X) * Rnd, 0.0,
                           C.Lo.Z + (C.Hi.Z - C.Lo.Z) * Rnd);
                     P.Y := 0.5 + Terrain.Height (P.X, P.Z);
                     exit when Inside (C, P.X, P.Z);
                  end loop;
                  if Inside (C, P.X, P.Z) then
                     Spawn_Ghost (G, P);
                     G.Pos := P;
                     G.Vel := 0.5 * G.Vel;
                  end if;
               end;
            end if;
         else
            G.Phase := G.Phase + Dt;
            if G.Swoop > 0.0 then
               --  diving at the car and on through it
               G.Swoop := G.Swoop - Dt;
            else
               --  drift about, turning now and then
               if Rnd < Dt / 3.0 then
                  G.Vel := (1.8 * Sym, 0.0, 1.8 * Sym);
               end if;
               --  sometimes one comes for you
               declare
                  D : constant Vec3 := Car_Pos + Vec3'(0.0, 1.0, 0.0) - G.Pos;
               begin
                  if Length (D) < 35.0 and then Rnd < Dt / 12.0 then
                     G.Vel := (9.0 / Length (D)) * D;
                     G.Swoop := Length (D) / 9.0 + 2.0;
                     G.Wooed := False;
                  end if;
               end;
            end if;
            --  cemetery ghosts stay among their graves (unless chasing you)
            if Home > 0 and then G.Swoop <= 0.0 then
               declare
                  C    : Cemetery renames Cemeteries (Home);
                  Next : constant Vec3 := G.Pos + 2.0 * G.Vel;
               begin
                  if not Inside (C, Next.X, Next.Z) then
                     G.Vel := (-1.0) * G.Vel;   --  back among the graves
                  end if;
                  G.Vel := Float'Min (1.0, 1.0 / Float'Max (0.01, Length (G.Vel))) * G.Vel;
               end;
            end if;
            if Ada.Environment_Variables.Exists ("PARIS_FREEZE") then
               G.Vel := (0.0, 0.0, 0.0);
            end if;
            G.Pos := G.Pos + Dt * G.Vel;
            if G.Swoop <= 0.0 then
               --  bob up and down at a ghostly height
               G.Pos.Y := G.Pos.Y + (2.6 + 0.5 * Sin (G.Phase * 1.3)
                                     + Terrain.Height (G.Pos.X, G.Pos.Z) - G.Pos.Y) * Dt;
            end if;
            declare
               D  : constant Vec3 := G.Pos - Listener;
               R  : constant Float := Length (D);
               DH : constant Float := Float'Max (0.5, Sqrt (D.X * D.X + D.Z * D.Z));
            begin
               if R < 14.0 and then not G.Wooed then
                  G.Wooed := True;
                  Sound.Wooo (Float'Min (1.0, 8.0 / (R + 2.0)),
                              (D.X * Cos (Listener_Heading) + D.Z * Sin (Listener_Heading)) / DH);
               end if;
               if R > 22.0 and then G.Swoop <= 0.0 then
                  G.Wooed := False;
               end if;
               if R > 120.0 and then Home = 0 then
                  G.Alive := False;
               end if;
            end;
         end if;
         end;
      end loop;
   end Update;

   procedure Draw (Model_Loc : GL.GLint) is
      use GL;
   begin
      Shaders.Set (Model_Loc, Identity);
      for C of Cemeteries (1 .. Cemetery_Count) loop
         if C.Built then
            Meshes.Draw (C.Graves);
         end if;
      end loop;
      for I in 1 .. (if Active then Pumpkin_Count else 0) loop
         declare
            P : Pumpkin renames Pumpkins (I);
            S : constant Float := P.Size;
            M : Mat4 := Translation (P.Pos) * Rotation_Y (P.Yaw);
         begin
            M (0) := M (0) * S;  M (1) := M (1) * S;  M (2) := M (2) * S;
            M (4) := M (4) * S;  M (5) := M (5) * S;  M (6) := M (6) * S;
            M (8) := M (8) * S;  M (9) := M (9) * S;  M (10) := M (10) * S;
            Shaders.Set (Model_Loc, M);
            Meshes.Draw (Pumpkin_Mesh);
         end;
      end loop;
      glEnable (GL_SAMPLE_ALPHA_TO_COVERAGE);
      for G of Ghosts loop
         if G.Alive then
            declare
               Heading : constant Float :=
                 (if abs G.Vel.X + abs G.Vel.Z < 0.01 then G.Phase
                  else Arctan (G.Vel.X, -G.Vel.Z));
               Sway    : constant Float := 0.15 * Sin (G.Phase * 2.1);
               M : Mat4 := Translation (G.Pos) * Rotation_Y (-Heading)
                 * Rotation_Z (Sway) * Rotation_X (-0.15);
            begin
               --  a little larger than life
               for K in 0 .. 10 loop
                  if K mod 4 /= 3 then
                     M (K) := M (K) * 1.35;
                  end if;
               end loop;
               Shaders.Set (Model_Loc, M);
               Meshes.Draw (Ghost_Mesh);
            end;
         end if;
      end loop;
      glDisable (GL_SAMPLE_ALPHA_TO_COVERAGE);
   end Draw;

end Halloween;
