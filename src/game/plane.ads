--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Flight mode: a small high-wing plane with arcade flight physics, for
--  seeing the city from above.

with GL;
with Math3D;

package Plane is

   type Controls is record
      Throttle_Up, Throttle_Down : Boolean := False;
      Nose_Down, Nose_Up         : Boolean := False;
      Roll_Left, Roll_Right      : Boolean := False;
   end record;

   type State is record
      Pos      : Math3D.Vec3 := (0.0, 120.0, 0.0);
      Heading  : Float := 0.0;   --  radians, 0 = north like the car
      Pitch    : Float := 0.0;   --  nose up positive
      Roll     : Float := 0.0;   --  right wing down positive
      Speed    : Float := 45.0;  --  m/s
      Throttle : Float := 0.6;   --  0 .. 1
      Prop     : Float := 0.0;   --  propeller angle
      Crashed  : Float := 0.0;   --  seconds left of the crash pause
   end record;

   procedure Start (S : out State; X, Z, Heading : Float);
   --  Airborne at 120 m over (X, Z)

   procedure Update (S : in out State; C : Controls; Dt : Float);
   --  Fly, and crash into the ground or buildings (then restart above)

   function Forward (S : State) return Math3D.Vec3;
   function Model_Matrix (S : State) return Math3D.Mat4;

   procedure Create_Mesh;

   procedure Draw (S : State; Model_Loc : GL.GLint);
   --  Body and spinning propeller; sets the model matrix uniform

end Plane;
