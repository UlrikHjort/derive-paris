--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Environment_Variables;
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Numerics.Float_Random;

with Figures;
with Geo;
with Meshes;
with Shaders;
with Sound;
with Terrain;
with Tower;

package body Extras is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;

   Pi : constant := Ada.Numerics.Pi;
   Mat_Paint : constant := 54.0;   --  glossy, in uCarColor
   Mat_Cloth : constant := 30.0;   --  matt, in uCarColor
   Mat_Wood  : constant := 13.0;

   Gen : Ada.Numerics.Float_Random.Generator;
   Seeded : Boolean := False;
   function Rnd return Float is (Ada.Numerics.Float_Random.Random (Gen));

   Clock : Float := 0.0;
   Day   : Boolean := True;

   procedure Face (A, B, C, D, N : Vec3; Mat : Float) is
   begin
      if Dot (Cross (B - A, D - A), N) >= 0.0 then
         Meshes.Quad (A, B, C, D, Mat);
      else
         Meshes.Quad (D, C, B, A, Mat);
      end if;
   end Face;

   ---------------------------------------------------------------------------
   --  The boats: a hull along -Z, a mast, a sail on each side

   Hull_M, Sail_M : Meshes.Mesh;
   Built : Boolean := False;

   Pond_C : Vec3 := (0.0, 0.0, 0.0);
   Pond_R : constant := 24.0;      --  the water they keep to

   type Boat is record
      P, V   : Vec3 := (0.0, 0.0, 0.0);
      Yaw    : Float := 0.0;
      Hull, Sail : Vec3 := (1.0, 1.0, 1.0);
   end record;
   Boats : array (1 .. 9) of Boat;
   Boats_Set : Boolean := False;
   Wind_Dir : Float := 0.7;

   type Child is record
      Angle : Float := 0.0;
      Coat  : Vec3 := (0.5, 0.5, 0.5);
      Poke  : Float := 0.0;
   end record;
   Children : array (1 .. 7) of Child;

   ---------------------------------------------------------------------------
   --  The parachutist

   type Jump_Phase is (None, Falling, Floating, Landed, Walking_Off);
   type Jumper is record
      Phase : Jump_Phase := None;
      P, V  : Vec3 := (0.0, 0.0, 0.0);
      T     : Float := 0.0;
      Canopy : Vec3 := (0.9, 0.2, 0.1);
      Target : Vec3 := (0.0, 0.0, 0.0);
   end record;
   Para : Jumper;
   Next_Jump : Float := 20.0;
   Canopy_M, Bundle_M : Meshes.Mesh;
   Canopy_Size : constant := 1.7;   --  (a little big: to be seen from afar)
   Harness_Y   : constant := 1.7;   --  where the lines meet, in the mesh
   Folding     : constant := 6.0;   --  seconds on the ground, gathering it in

   procedure Build is
   begin
      Meshes.Start;
      Meshes.Box (-0.11, 0.11, 0.0, 0.12, -0.32, 0.3, Mat_Paint, Top_Inset_Front => 0.12);
      Meshes.Box (-0.012, 0.012, 0.12, 0.78, 0.0, 0.024, Mat_Wood);          --  mast
      Meshes.Finish (Hull_M);
      Meshes.Start;
      Face ((0.0, 0.16, 0.02), (0.0, 0.78, 0.02), (0.0, 0.78, 0.02), (0.0, 0.16, 0.36), (1.0, 0.0, 0.0), Mat_Cloth);
      Face ((0.0, 0.16, 0.02), (0.0, 0.78, 0.02), (0.0, 0.78, 0.02), (0.0, 0.16, 0.36), (-1.0, 0.0, 0.0), Mat_Cloth);
      Face ((0.0, 0.2, -0.02), (0.0, 0.66, -0.02), (0.0, 0.66, -0.02), (0.0, 0.2, -0.3), (1.0, 0.0, 0.0), Mat_Cloth);
      Face ((0.0, 0.2, -0.02), (0.0, 0.66, -0.02), (0.0, 0.66, -0.02), (0.0, 0.2, -0.3), (-1.0, 0.0, 0.0), Mat_Cloth);
      Meshes.Finish (Sail_M);
      --  a canopy: an arched strip of cells over the jumper's head
      Meshes.Start;
      for K in 0 .. 7 loop
         declare
            A0 : constant Float := -0.9 + 1.8 * Float (K) / 8.0;
            A1 : constant Float := -0.9 + 1.8 * Float (K + 1) / 8.0;
            R  : constant Float := 4.0;
            P0 : constant Vec3 := (R * Sin (A0), 6.0 + R * (Cos (A0) - 1.0), 0.0);
            P1 : constant Vec3 := (R * Sin (A1), 6.0 + R * (Cos (A1) - 1.0), 0.0);
         begin
            Face (P0 + Vec3'(0.0, 0.0, -1.1), P1 + Vec3'(0.0, 0.0, -1.1), P1 + Vec3'(0.0, 0.0, 1.1),
                  P0 + Vec3'(0.0, 0.0, 1.1), (0.0, 1.0, 0.0), Mat_Cloth);
            Face (P0 + Vec3'(0.0, -0.05, -1.1), P1 + Vec3'(0.0, -0.05, -1.1), P1 + Vec3'(0.0, -0.05, 1.1),
                  P0 + Vec3'(0.0, -0.05, 1.1), (0.0, -1.0, 0.0), Mat_Cloth);
         end;
      end loop;
      --  the lines down to the harness
      for Side in -1 .. 1 loop
         if Side /= 0 then
            Face ((3.6 * Float (Side), 5.4, -0.9), (3.6 * Float (Side) + 0.01, 5.4, -0.9),
                  (0.05, 1.7, 0.0), (0.0, 1.7, 0.0), (0.0, 0.0, 1.0), 17.0);
            Face ((3.6 * Float (Side), 5.4, 0.9), (3.6 * Float (Side) + 0.01, 5.4, 0.9),
                  (0.05, 1.7, 0.0), (0.0, 1.7, 0.0), (0.0, 0.0, 1.0), 17.0);
         end if;
      end loop;
      Meshes.Finish (Canopy_M);
      --  the canopy gathered up, carried under the arm
      Meshes.Start;
      Meshes.Box (-0.2, 0.2, 0.95, 1.3, 0.1, 0.42, Mat_Cloth);
      Meshes.Finish (Bundle_M);
      Built := True;
   end Build;

   function Heading (D : Vec3) return Float is
     (if D.X = 0.0 and then D.Z = 0.0 then 0.0 else Arctan (D.X, -D.Z));

   procedure Set_Up_Pond is
      X, Z : Long_Float;
      Colours : constant array (0 .. 6) of Vec3 :=
        ((0.85, 0.15, 0.12), (0.1, 0.3, 0.75), (0.95, 0.75, 0.1), (0.15, 0.55, 0.3),
         (0.95, 0.95, 0.92), (0.6, 0.2, 0.6), (0.95, 0.45, 0.1));
   begin
      Geo.To_Local (48.846927, 2.337241, X, Z);
      Pond_C := (Float (X), Terrain.Height (Float (X), Float (Z)), Float (Z));
      for I in Boats'Range loop
         declare
            A : constant Float := 2.0 * Pi * Rnd;
            R : constant Float := Pond_R * Sqrt (Rnd);
         begin
            Boats (I) := (P => Pond_C + Vec3'(R * Cos (A), 0.0, R * Sin (A)),
                          V => (0.0, 0.0, 0.0), Yaw => 2.0 * Pi * Rnd,
                          Hull => Colours ((I * 3) mod 7), Sail => Colours ((I * 5 + 4) mod 7));
         end;
      end loop;
      for I in Children'Range loop
         Children (I) := (Angle => 2.0 * Pi * Float (I) / 7.0 + 0.3 * Rnd,
                          Coat => Colours ((I * 2 + 1) mod 7), Poke => Rnd * 5.0);
      end loop;
      Boats_Set := True;
   end Set_Up_Pond;

   procedure Update (Dt, Hour, Night : Float; Near : Vec3) is
   begin
      if not Seeded then
         Ada.Numerics.Float_Random.Reset (Gen);
         Seeded := True;
      end if;
      if not Boats_Set then
         Set_Up_Pond;
         if Ada.Environment_Variables.Exists ("PARIS_JUMP") then
            Next_Jump := 2.0;
         end if;
      end if;
      Clock := Clock + Dt;
      Day := Hour >= 9.5 and then Hour < 19.0 and then Night < 0.3;
      Wind_Dir := Wind_Dir + 0.03 * Dt * Sin (Clock * 0.05);

      --  the boats sail before the wind, and turn back at the edge (where
      --  a child pushes them off again)
      if (Near.X - Pond_C.X) ** 2 + (Near.Z - Pond_C.Z) ** 2 < 400.0 ** 2 then
         for B of Boats loop
            declare
               Wind : constant Vec3 := (Cos (Wind_Dir), 0.0, Sin (Wind_Dir));
               Off  : constant Vec3 := B.P - Pond_C;
               D    : constant Float := Sqrt (Off.X ** 2 + Off.Z ** 2);
            begin
               B.V := B.V + Dt * (0.35 * Wind - 0.3 * B.V);
               if D > Pond_R then
                  --  pushed off from the side, back towards the middle
                  B.V := (-0.9 / D) * Vec3'(Off.X, 0.0, Off.Z) + Vec3'(0.3 * (Rnd - 0.5), 0.0, 0.3 * (Rnd - 0.5));
                  B.P := Pond_C + ((Pond_R - 0.2) / D) * Vec3'(Off.X, 0.0, Off.Z);
               end if;
               B.P := B.P + Dt * B.V;
               B.P.Y := Pond_C.Y + 0.02 + 0.03 * Sin (Clock * 2.0 + B.P.X);
               if B.V.X ** 2 + B.V.Z ** 2 > 0.001 then
                  B.Yaw := B.Yaw + 2.0 * Dt * Sin (Heading (B.V) - B.Yaw);
               end if;
            end;
         end loop;
         for C of Children loop
            C.Poke := C.Poke + Dt;
            if C.Poke > 6.0 then
               C.Poke := 0.0;
            end if;
         end loop;
      end if;

      --  the parachutist: now and then by day, when you are near the tower
      if Tower.Known then
         declare
            TX, TZ : Float;
         begin
            Tower.Centre (TX, TZ);
            case Para.Phase is
               when None =>
                  Next_Jump := Next_Jump - Dt;
                  if Next_Jump <= 0.0 then
                     Next_Jump := (if Ada.Environment_Variables.Exists ("PARIS_JUMP") then 8.0 else 60.0 + 120.0 * Rnd);
                     if (Day or else Ada.Environment_Variables.Exists ("PARIS_JUMP"))
                       and then (Near.X - TX) ** 2 + (Near.Z - TZ) ** 2 < 900.0 ** 2
                     then
                        declare
                           A : constant Float := 2.0 * Pi * Rnd;
                        begin
                           Para := (Phase => Falling, T => 0.0,
                                    P => (TX + 4.0 * Cos (A), Tower.Top_Floor_Y + 1.5, TZ + 4.0 * Sin (A)),
                                    V => (9.0 * Cos (A), 1.5, 9.0 * Sin (A)),   --  a run and a leap
                                    Canopy => (if Rnd < 0.33 then Vec3'(1.0, 0.12, 0.05)
                                               elsif Rnd < 0.5 then Vec3'(0.08, 0.35, 1.0)
                                               else Vec3'(1.0, 0.8, 0.0)),
                                    --  a landing on the lawn of the Champ-de-Mars, south-east of the tower
                                    Target => (TX + 315.0 + 30.0 * Rnd, 0.0, TZ + 305.0 + 30.0 * Rnd));
                           --  PARIS_JUMP=low: from just above the landing (testing)
                           if Ada.Environment_Variables.Value ("PARIS_JUMP", "") = "low" then
                              Para.P := Para.Target + Vec3'(0.0, Terrain.Height (Para.Target.X, Para.Target.Z) + 110.0, 0.0);
                              Para.V := (0.0, 0.0, 0.0);
                           end if;
                        end;
                     end if;
                  end if;
               when Falling =>
                  Para.T := Para.T + Dt;
                  Para.V.Y := Para.V.Y - 9.81 * Dt;
                  Para.V.Y := Float'Max (Para.V.Y, -45.0);
                  Para.P := Para.P + Dt * Para.V;
                  if Para.T > 3.5 then
                     Para.Phase := Floating;
                     Para.T := 0.0;
                     declare
                        D : constant Float := Sqrt ((Near.X - Para.P.X) ** 2 + (Near.Z - Para.P.Z) ** 2
                                                    + (Para.P.Y - Terrain.Height (Near.X, Near.Z)) ** 2);
                     begin
                        if D < 500.0 then
                           Sound.Effect (Sound.Canopy, Float'Min (1.0, 100.0 / (D + 30.0)), 0.0);
                        end if;
                     end;
                  end if;
               when Floating =>
                  Para.T := Para.T + Dt;
                  declare
                     To : constant Vec3 := Para.Target - Para.P;
                     H  : constant Float := Sqrt (To.X ** 2 + To.Z ** 2);
                     G  : constant Float := Terrain.Height (Para.P.X, Para.P.Z);
                     --  slowing to a glide, and a flare just above the ground
                     Sink : constant Float :=
                       Float'Max ((if Para.P.Y - G < 8.0 then 1.2 else 4.5), -Para.V.Y * (1.0 - 2.0 * Dt));
                  begin
                     Para.V := (Para.V.X + Dt * (6.0 * To.X / Float'Max (H, 1.0) - Para.V.X) * 0.3, -Sink,
                                Para.V.Z + Dt * (6.0 * To.Z / Float'Max (H, 1.0) - Para.V.Z) * 0.3);
                     Para.P := Para.P + Dt * Para.V;
                     if Para.P.Y <= G then
                        Para.P.Y := G;
                        Para.Phase := Landed;
                        Para.T := 0.0;
                     end if;
                  end;
               when Landed =>
                  Para.T := Para.T + Dt;
                  Para.P.Y := Terrain.Height (Para.P.X, Para.P.Z);
                  if Para.T > Folding then
                     Para.Phase := Walking_Off;
                     Para.T := 0.0;
                     --  away from the tower, down the Champ-de-Mars
                     Para.V := (1.4 * 0.8, 0.0, 1.4 * 0.6);
                  end if;
               when Walking_Off =>
                  --  until nobody is looking any more
                  Para.T := Para.T + Dt;
                  Para.P := Para.P + Dt * Para.V;
                  Para.P.Y := Terrain.Height (Para.P.X, Para.P.Z);
                  if (Near.X - Para.P.X) ** 2 + (Near.Z - Para.P.Z) ** 2 > 150.0 ** 2
                    or else Para.T > 120.0
                  then
                     Para.Phase := None;
                  end if;
            end case;
         end;
      end if;
   end Update;

   procedure Draw (Model, Paint, Skin, Legs : GL.GLint; Cam : Vec3) is
      Skins : constant array (0 .. 3) of Vec3 :=
        ((0.86, 0.68, 0.56), (0.76, 0.57, 0.44), (0.58, 0.40, 0.29), (0.40, 0.27, 0.19));
   begin
      if not Built then
         Build;
      end if;
      --  the boats and the children
      if Day and then Boats_Set and then (Cam.X - Pond_C.X) ** 2 + (Cam.Z - Pond_C.Z) ** 2 < 250.0 ** 2 then
         for B of Boats loop
            declare
               M : constant Mat4 := Translation (B.P) * Rotation_Y (-B.Yaw)
                 * Rotation_Z (0.08 * Sin (Clock * 1.7 + B.P.Z)) * Scale (1.6);
            begin
               Shaders.Set (Model, M);
               Shaders.Set (Paint, B.Hull);
               Meshes.Draw (Hull_M);
               Shaders.Set (Paint, B.Sail);
               Meshes.Draw (Sail_M);
            end;
         end loop;
         Figures.Set_Locations ((Model, Paint, Skin, Legs));
         for I in Children'Range loop
            declare
               C : Child renames Children (I);
               R : constant Float := Pond_R + 10.0;   --  on the rim
               P : constant Vec3 := Pond_C + Vec3'(R * Cos (C.Angle), 0.0, R * Sin (C.Angle));
            begin
               Figures.Person
                 (Translation ((P.X, Terrain.Height (P.X, P.Z), P.Z))
                  * Rotation_Y (-Heading (Pond_C - P)) * Scale (0.62),
                  C.Coat, Skins (I mod 4), (0.2, 0.2, 0.3),
                  Arm_Up => (if C.Poke < 1.2 then -1.3 + 0.4 * Sin (C.Poke * 5.0) else -0.6));
            end;
         end loop;
      end if;
      --  the parachutist
      if Para.Phase /= None and then (Cam.X - Para.P.X) ** 2 + (Cam.Z - Para.P.Z) ** 2 < 1500.0 ** 2 then
         Figures.Set_Locations ((Model, Paint, Skin, Legs));
         declare
            Yaw : constant Float := Heading (Para.V);
         begin
            Figures.Person
              (Translation (Para.P) * Rotation_Y (-Yaw)
               * (if Para.Phase = Falling then Rotation_X (-1.3) else Identity),
               (0.1, 0.1, 0.12), (0.8, 0.62, 0.5), (0.1, 0.1, 0.12),
               Stride => (if Para.Phase = Walking_Off then 0.45 * Sin (Para.T * 5.5) else 0.0),
               Arm_Up => (case Para.Phase is
                             when Falling => -2.6,
                             when Floating => -2.9,
                             when Landed => -0.9 + 0.3 * Sin (Para.T * 4.0),
                             when others => 0.0));
            Shaders.Set (Paint, Para.Canopy);
            case Para.Phase is
               when Floating =>
                  Shaders.Set (Model, Translation (Para.P) * Rotation_Y (-Yaw + Pi / 2.0)
                                      * Translation ((0.0, Harness_Y, 0.0))
                                      * Scale (Canopy_Size * Float'Min (1.0, 0.2 + Para.T * 1.5))
                                      * Translation ((0.0, -Harness_Y, 0.0)));
                  Meshes.Draw (Canopy_M);
               when Landed =>
                  --  it sinks down behind them, then is drawn in
                  declare
                     Sunk  : constant Float := Float'Min (1.0, Para.T / 1.5);
                     Drawn : constant Float :=
                       Float'Max (0.0, Float'Min (1.0, (Para.T - 1.5) / (Folding - 2.0)));
                     Wide  : constant Float := Canopy_Size * (1.0 - 0.95 * Drawn);
                     M     : Mat4 := Identity;
                  begin
                     M (0) := Wide;
                     M (5) := Canopy_Size * Float'Max (0.012, 1.0 - Sunk);
                     M (10) := Wide;
                     Shaders.Set (Model, Translation (Para.P) * Rotation_Y (-Yaw)
                                         * Translation ((0.0, 0.02, 1.0 + 7.0 * Sunk * (1.0 - Drawn)))
                                         * Rotation_Y (Pi / 2.0) * M);
                     Meshes.Draw (Canopy_M);
                  end;
               when Walking_Off =>
                  Shaders.Set (Model, Translation (Para.P) * Rotation_Y (-Yaw));
                  Meshes.Draw (Bundle_M);
               when others =>
                  null;
            end case;
         end;
      end if;
   end Draw;

end Extras;
