--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Numerics.Float_Random;

with Meshes;
with Shaders;

package body Sleigh is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;
   use type GL.GLint;

   type Float_Array is array (Positive range <>) of Float;

   function Scaling (S : Float) return Mat4 is
      M : Mat4 := Identity;
   begin
      M (0) := S;
      M (5) := S;
      M (10) := S;
      return M;
   end Scaling;

   Mat_Fur  : constant := 39.0;
   Mat_Gold : constant := 38.0;
   Mat_Hide : constant := 13.0;   --  brown

   Sleigh_Mesh, Deer, Rudolph : Meshes.Mesh;

   Gen : Ada.Numerics.Float_Random.Generator;
   function Rnd return Float is (Ada.Numerics.Float_Random.Random (Gen));

   Flying   : Boolean := False;
   Pos, Vel : Vec3 := (0.0, 0.0, 0.0);
   Clock    : Float := 0.0;
   Wait     : Float := 60.0;     --  seconds until he may come again
   Closest  : Float := Float'Last;
   Laughed  : Boolean := False;
   Laugh    : Boolean := False;
   Bells    : Float := 0.0;
   Side     : Float := 0.0;
   Ear_Head : Float := 0.0;

   Scale : constant := 1.6;   --  a little larger than life, to be seen

   procedure Create_Mesh is
      use Meshes;
   begin
      --  The sleigh with Santa and his sack (front is -Z)
      Start;
      Box (-0.8, 0.8, 0.35, 1.15, -1.1, 1.4, Mat_Paint,
           Top_Inset_X => 0.05, Top_Inset_Front => 0.35);
      Box (-0.8, 0.8, 1.15, 1.9, 1.05, 1.45, Mat_Paint);              --  seat back
      Box (-0.85, 0.85, 1.1, 1.2, -1.15, 1.45, Mat_Gold);             --  gold rim
      for X of Float_Array'(-0.7, 0.62) loop
         Box (X, X + 0.08, 0.0, 0.1, -1.7, 1.5, Mat_Gold);            --  runners
         Box (X, X + 0.08, 0.1, 0.38, -1.25, -1.15, Mat_Gold);
         Box (X, X + 0.08, 0.1, 0.38, 1.0, 1.1, Mat_Gold);
         Box (X, X + 0.08, 0.1, 0.55, -1.75, -1.65, Mat_Gold);        --  curl
      end loop;
      Box (-0.45, 0.45, 1.1, 2.05, 0.1, 0.8, Mat_Cloth);              --  Santa
      Box (-0.46, 0.46, 1.4, 1.48, 0.09, 0.81, Mat_Tyre);             --  belt
      Box (-0.17, 0.17, 2.05, 2.4, 0.25, 0.58, Mat_Skin);             --  head
      Box (-0.19, 0.19, 1.85, 2.28, 0.15, 0.26, Mat_Fur);             --  beard
      Box (-0.19, 0.19, 2.38, 2.48, 0.23, 0.6, Mat_Fur);              --  brim
      Box (-0.16, 0.16, 2.48, 2.72, 0.27, 0.6, Mat_Cloth, Top_Inset_X => 0.1,
           Top_Inset_Front => 0.15);
      Box (-0.06, 0.06, 2.66, 2.78, 0.5, 0.62, Mat_Fur);              --  pompom
      Box (-0.55, -0.35, 1.3, 1.5, -0.3, 0.2, Mat_Cloth);             --  arms on
      Box (0.35, 0.55, 1.3, 1.5, -0.3, 0.2, Mat_Cloth);               --  the reins
      Box (-0.55, 0.55, 1.15, 2.2, 0.85, 1.45, Mat_Hide);             --  the sack
      Box (-0.2, 0.2, 2.2, 2.4, 1.0, 1.3, Mat_Gold);                  --  its tie
      Box (-0.03, 0.03, 1.4, 1.45, -9.0, -1.1, Mat_Gold);             --  reins
      Finish (Sleigh_Mesh);

      --  A reindeer (one mesh, drawn eight times)
      for Red_Nose in Boolean loop
         Start;
         Box (-0.22, 0.22, 0.95, 1.4, -0.7, 0.6, Mat_Hide);           --  body
         Box (-0.12, 0.12, 1.3, 1.75, -0.95, -0.6, Mat_Hide);         --  neck
         Box (-0.13, 0.13, 1.6, 1.85, -1.3, -0.85, Mat_Hide);         --  head
         Box (-0.1, -0.06, 1.85, 2.25, -1.0, -0.94, Mat_Tyre);        --  antlers
         Box (0.06, 0.1, 1.85, 2.25, -1.0, -0.94, Mat_Tyre);
         Box (-0.25, -0.06, 2.1, 2.16, -1.05, -0.9, Mat_Tyre);
         Box (0.06, 0.25, 2.1, 2.16, -1.05, -0.9, Mat_Tyre);
         Box (-0.08, 0.08, 1.88, 1.92, -0.7, -0.62, Mat_Gold);        --  bell
         if Red_Nose then
            Box (-0.07, 0.07, 1.62, 1.76, -1.4, -1.28, Mat_Taillight);
         else
            Box (-0.05, 0.05, 1.64, 1.72, -1.34, -1.28, Mat_Tyre);
         end if;
         for X of Float_Array'(-0.18, 0.1) loop                       --  legs
            for Z of Float_Array'(-0.55, 0.4) loop
               Box (X, X + 0.08, 0.2, 0.98, Z, Z + 0.1, Mat_Hide);
            end loop;
         end loop;
         Box (-0.05, 0.05, 1.25, 1.4, 0.6, 0.72, Mat_Fur);            --  tail
         if Red_Nose then
            Finish (Rudolph);
         else
            Finish (Deer);
         end if;
      end loop;
      Ada.Numerics.Float_Random.Reset (Gen);
      Wait := 30.0 + 90.0 * Rnd;
   end Create_Mesh;

   --  Usually he comes down the street you are looking along, from far
   --  ahead, just above the rooftops, and passes right over you; now and
   --  then he crosses the sky somewhere else
   procedure Start_Flight (Listener : Vec3; Down_The_Street : Boolean := False) is
      Down_Street : constant Boolean := Down_The_Street or else Rnd < 0.75;
      --  flying towards you from where you look: against your heading
      A    : constant Float :=
        (if Down_Street then Ear_Head + Ada.Numerics.Pi / 2.0
         else 2.0 * Ada.Numerics.Pi * Rnd);
      Miss : constant Float := 40.0 + 160.0 * Rnd;     --  how far he passes from you
      Dir  : constant Vec3 := (Cos (A), 0.0, Sin (A));
      Across : constant Vec3 := (-Dir.Z, 0.0, Dir.X);
   begin
      if Down_Street then
         Pos := Listener - 750.0 * Dir + (6.0 * (2.0 * Rnd - 1.0)) * Across;
         Pos.Y := 38.0 + 6.0 * Rnd;
      else
         Pos := Listener - 1400.0 * Dir + Miss * Across;
         Pos.Y := 55.0 + 50.0 * Rnd;
      end if;
      Vel := 22.0 * Dir;
      Flying := True;
      Closest := Float'Last;
      Laughed := False;
   end Start_Flight;

   procedure Start_At (Where : Vec3; Heading : Float) is
   begin
      Pos := Where;
      Vel := 22.0 * Vec3'(Sin (Heading), 0.0, -Cos (Heading));
      Flying := True;
      Closest := Float'Last;
      Laughed := False;
   end Start_At;

   procedure Update (Dt : Float; Season : Boolean; Listener : Vec3) is
   begin
      Clock := Clock + Dt;
      Laugh := False;
      if not Flying then
         Bells := 0.0;
         Wait := Wait - Dt;
         if Season and then Wait <= 0.0 then
            --  not every time: sometimes he is busy elsewhere
            if Rnd < 0.5 then
               Start_Flight (Listener);
            end if;
            Wait := 120.0 + 240.0 * Rnd;
         end if;
         return;
      end if;
      Pos := Pos + Dt * Vel;
      Pos.Y := Pos.Y + 0.6 * Sin (Clock * 0.8) * Dt;   --  gentle rise and fall
      declare
         D  : constant Vec3 := Pos - Listener;
         R  : constant Float := Length (D);
         DH : constant Float := Float'Max (0.5, Sqrt (D.X * D.X + D.Z * D.Z));
      begin
         Bells := Float'Min (1.0, 60.0 / (R + 20.0));
         Side := (D.X * Cos (Ear_Head) + D.Z * Sin (Ear_Head)) / DH;
         if R < Closest then
            Closest := R;
         elsif not Laughed and then Closest < 400.0 then
            Laughed := True;
            Laugh := True;   --  he just went past
         end if;
         if R > 1600.0 and then Closest < R - 200.0 then
            Flying := False;
         end if;
      end;
   end Update;

   procedure Draw (Model_Loc, Red_Loc, Skin_Loc : GL.GLint) is
   begin
      if not Flying then
         return;
      end if;
      declare
         Heading : constant Float := Arctan (Vel.X, -Vel.Z);
         M : constant Mat4 :=
           Translation (Pos) * Rotation_Y (-Heading) * Scaling (Scale);
      begin
      if Red_Loc >= 0 then
         Shaders.Set (Red_Loc, Vec3'(0.75, 0.05, 0.05));
         Shaders.Set (Skin_Loc, Vec3'(0.92, 0.74, 0.62));
      end if;
      Shaders.Set (Model_Loc, M);
      Meshes.Draw (Sleigh_Mesh);
      --  four pairs, galloping out of step, Rudolph in front
      for Row in 0 .. 4 loop
         for X of Float_Array'(-0.55, 0.55) loop
            if Row < 4 or else X > 0.0 then
               declare
                  Gallop : constant Float := Clock * 7.0 + Float (Row) * 1.3 + X;
                  DM : constant Mat4 :=
                    M * Translation (((if Row = 4 then 0.0 else X),
                                      0.15 * Sin (Gallop),
                                      -3.2 - 2.0 * Float (Row)))
                      * Rotation_X (0.12 * Sin (Gallop + 0.8));
               begin
                  Shaders.Set (Model_Loc, DM);
                  Meshes.Draw ((if Row = 4 then Rudolph else Deer));
               end;
            end if;
         end loop;
      end loop;
      end;
   end Draw;

   function Jingle return Float is (Bells);

   function Dust_Point return Vec3 is
      Heading : constant Float :=
        (if Vel.X = 0.0 and then Vel.Z = 0.0 then 0.0 else Arctan (Vel.X, -Vel.Z));
   begin
      --  behind the sleigh, a little below the runners
      return Pos + Vec3'(-Sin (Heading) * 2.6 * Scale, 0.3, Cos (Heading) * 2.6 * Scale);
   end Dust_Point;

   function Visible return Boolean is (Flying);
   function Ho_Ho_Now return Boolean is (Laugh);
   function Pan return Float is (Side);

   procedure Set_Listener_Heading (Heading : Float) is
   begin
      Ear_Head := Heading;
   end Set_Listener_Heading;

end Sleigh;
