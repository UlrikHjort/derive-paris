--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Numerics.Float_Random;

with Meshes;
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
   Ghosts : array (1 .. 4) of Ghost;

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
      Ada.Numerics.Float_Random.Reset (Gen);
   end Create_Mesh;

   procedure Spawn_Ghost (G : in out Ghost; Near : Vec3) is
      A : constant Float := 2.0 * Ada.Numerics.Pi * Rnd;
      D : constant Float := 30.0 + 50.0 * Rnd;
   begin
      G := (Alive => True,
            Pos   => (Near.X + D * Cos (A), 2.0 + 2.0 * Rnd, Near.Z + D * Sin (A)),
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
      Clock := Clock + Dt;
      if not On then
         Pumpkin_Count := 0;
         for G of Ghosts loop
            G.Alive := False;
         end loop;
         return;
      end if;

      --  a pumpkin at about one lamp in three
      Look_Again := Look_Again - Dt;
      if Look_Again <= 0.0 then
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
                          (Pos  => (PX, 0.14, PZ),
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
      for G of Ghosts loop
         if not Dark then
            G.Alive := False;
         elsif not G.Alive then
            if Rnd < Dt / 4.0 then
               Spawn_Ghost (G, Listener);
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
            G.Pos := G.Pos + Dt * G.Vel;
            if G.Swoop <= 0.0 then
               --  bob up and down at a ghostly height
               G.Pos.Y := G.Pos.Y + (2.6 + 0.5 * Sin (G.Phase * 1.3) - G.Pos.Y) * Dt;
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
               if R > 120.0 then
                  G.Alive := False;
               end if;
            end;
         end if;
      end loop;
   end Update;

   procedure Draw (Model_Loc : GL.GLint) is
      use GL;
   begin
      if not Active then
         return;
      end if;
      for I in 1 .. Pumpkin_Count loop
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
            begin
               Shaders.Set (Model_Loc, Translation (G.Pos) * Rotation_Y (-Heading)
                            * Rotation_Z (Sway) * Rotation_X (-0.15));
               Meshes.Draw (Ghost_Mesh);
            end;
         end if;
      end loop;
      glDisable (GL_SAMPLE_ALPHA_TO_COVERAGE);
   end Draw;

end Halloween;
