--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;

with Meshes;
with Shaders;
with River;
with Terrain;
with World;

package body Plane is

   use Ada.Numerics.Elementary_Functions;
   use Math3D;

   Gravity     : constant := 9.81;
   Min_Speed   : constant := 18.0;
   Stall_Speed : constant := 24.0;
   Max_Roll    : constant := 1.2;
   Max_Pitch   : constant := 1.1;
   Start_Alt   : constant := 120.0;

   procedure Start (S : out State; X, Z, Heading : Float) is
   begin
      S := (Pos => (X, Start_Alt + Terrain.Height (X, Z), Z), Heading => Heading, others => <>);
   end Start;

   function Forward (S : State) return Vec3 is
     ((Sin (S.Heading) * Cos (S.Pitch), Sin (S.Pitch), -Cos (S.Heading) * Cos (S.Pitch)));

   function Model_Matrix (S : State) return Mat4 is
     (Translation (S.Pos) * Rotation_Y (-S.Heading) * Rotation_X (S.Pitch)
      * Rotation_Z (-S.Roll));

   procedure Approach (V : in out Float; Target, Rate : Float) is
   begin
      if V < Target then
         V := Float'Min (Target, V + Rate);
      else
         V := Float'Max (Target, V - Rate);
      end if;
   end Approach;

   procedure Update (S : in out State; C : Controls; Dt : Float) is
   begin
      if S.Crashed > 0.0 then
         S.Crashed := S.Crashed - Dt;
         if S.Crashed <= 0.0 then
            Start (S, S.Pos.X, S.Pos.Z, S.Heading);
         end if;
         return;
      end if;

      --  Engine
      if C.Auto then
         Approach (S.Throttle, C.Want_Throttle, 0.5 * Dt);
      elsif C.Throttle_Up then
         S.Throttle := Float'Min (1.0, S.Throttle + 0.5 * Dt);
      elsif C.Throttle_Down then
         S.Throttle := Float'Max (0.0, S.Throttle - 0.5 * Dt);
      end if;
      S.Prop := S.Prop + Dt * (20.0 + 60.0 * S.Throttle);

      --  Stick: roll with left/right, pitch with up/down (up = nose down,
      --  like pushing a control stick); the plane levels itself gently
      if C.Auto then
         Approach (S.Roll, C.Want_Roll, 1.6 * Dt);
      elsif C.Roll_Left then
         Approach (S.Roll, -Max_Roll, 1.6 * Dt);
      elsif C.Roll_Right then
         Approach (S.Roll, Max_Roll, 1.6 * Dt);
      else
         Approach (S.Roll, 0.0, 0.9 * Dt);
      end if;
      if C.Auto then
         Approach (S.Pitch, C.Want_Pitch, 0.8 * Dt);
      elsif C.Nose_Down then
         Approach (S.Pitch, -Max_Pitch, 0.8 * Dt);
      elsif C.Nose_Up then
         Approach (S.Pitch, Max_Pitch, 0.8 * Dt);
      else
         Approach (S.Pitch, 0.0, 0.15 * Dt);
      end if;

      --  Too slow: the nose drops
      if S.Speed < Stall_Speed then
         S.Pitch := S.Pitch - (Stall_Speed - S.Speed) * 0.08 * Dt;
      end if;

      --  Speed follows the throttle; climbing costs speed, diving gains
      S.Speed := S.Speed
        + ((25.0 + 50.0 * S.Throttle - S.Speed) * 0.35 - Gravity * Sin (S.Pitch)) * Dt;
      S.Speed := Float'Max (Min_Speed, S.Speed);

      --  Banked turn
      S.Heading := S.Heading + Gravity * Tan (S.Roll) / S.Speed * Dt * Cos (S.Pitch);
      S.Pos := S.Pos + (S.Speed * Dt) * Forward (S);

      --  Ground and buildings
      declare
         --  over the Seine: down to just above the water, under the bridges
         G : constant Float :=
           (if River.In_Channel (S.Pos.X, S.Pos.Z)
            then Terrain.Height (S.Pos.X, S.Pos.Z) - River.Depth + River.Lowest
            else Terrain.Height (S.Pos.X, S.Pos.Z) + 1.0);
      begin
         if S.Pos.Y < G or else World.Obstacle_At (S.Pos.X, S.Pos.Y, S.Pos.Z, 3.0, Up_Down => River.Clear) then
            S.Crashed := 2.0;
            S.Speed := 0.0;
            if S.Pos.Y < G then
               S.Pos.Y := G;
            end if;
         end if;
      end;
      if S.Pos.Y > 1500.0 then
         S.Pos.Y := 1500.0;
         S.Pitch := Float'Min (S.Pitch, 0.0);
      end if;
   end Update;

   ---------------------------------------------------------------------------
   --  Mesh: a Cessna-like high-wing plane, nose towards -Z
   ---------------------------------------------------------------------------

   Body_Mesh, Propeller : Meshes.Mesh;

   procedure Create_Mesh is
      use Meshes;
   begin
      Start;
      --  Fuselage, tapering to the tail
      Box (-0.6, 0.6, -0.2, 1.0, -3.4, 0.6, Mat_Paint,
           Top_Inset_X => 0.05, Top_Inset_Front => 0.9);
      Box (-0.55, 0.55, -0.15, 0.95, 0.6, 1.6, Mat_Paint);
      Box (-0.45, 0.45, 0.05, 0.85, 1.6, 4.6, Mat_Paint,
           Top_Inset_X => 0.25, Top_Inset_Back => 0.0);
      --  Cabin glazing
      Box (-0.61, 0.61, 0.35, 0.95, -1.9, 0.3, Mat_Paint, Side_Mat => Mat_Glass);
      --  High wing with red tips
      Box (-5.0, 5.0, 1.0, 1.15, -1.5, 0.0, Mat_Paint);
      Box (-5.2, -5.0, 0.98, 1.17, -1.5, 0.0, Mat_Taillight);
      Box (5.0, 5.2, 0.98, 1.17, -1.5, 0.0, Mat_Headlight);
      --  Wing struts
      Box (-2.2, -2.1, -0.1, 1.0, -0.8, -0.65, Mat_Tyre);
      Box (2.1, 2.2, -0.1, 1.0, -0.8, -0.65, Mat_Tyre);
      --  Tail
      Box (-1.9, 1.9, 0.5, 0.6, 3.7, 4.5, Mat_Paint);
      Box (-0.05, 0.05, 0.6, 2.2, 3.5, 4.6, Mat_Paint, Top_Inset_Front => 0.7);
      --  Landing gear
      Box (-1.1, -0.9, -0.85, -0.2, -0.6, -0.2, Mat_Tyre);
      Box (0.9, 1.1, -0.85, -0.2, -0.6, -0.2, Mat_Tyre);
      Box (-0.1, 0.1, -0.85, -0.2, -2.9, -2.6, Mat_Tyre);
      --  Spinner
      Box (-0.2, 0.2, 0.2, 0.6, -3.65, -3.4, Mat_Tyre);
      Finish (Body_Mesh);

      Start;
      Box (-0.06, 0.06, -0.95, 0.95, -0.04, 0.04, Mat_Tyre);
      Finish (Propeller);
   end Create_Mesh;

   procedure Draw (S : State; Model_Loc : GL.GLint) is
      M : constant Mat4 := Model_Matrix (S);
   begin
      Shaders.Set (Model_Loc, M);
      Meshes.Draw (Body_Mesh);
      Shaders.Set (Model_Loc, M * Translation ((0.0, 0.4, -3.7)) * Rotation_Z (S.Prop));
      Meshes.Draw (Propeller);
   end Draw;

end Plane;
