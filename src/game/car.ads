--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The player's car: simple arcade physics (bicycle model) and its mesh.

with Math3D;

package Car is

   type Controls is record
      Throttle  : Boolean := False;
      Brake     : Boolean := False;
      Left      : Boolean := False;
      Right     : Boolean := False;
      Handbrake : Boolean := False;
   end record;

   type State is record
      X, Z    : Float := 0.0;
      Heading : Float := 0.0;   --  radians, 0 = north (-Z), pi/2 = east
      Speed   : Float := 0.0;   --  m/s along the heading
      Steer   : Float := 0.0;   --  front wheel angle, radians
      Bumped  : Boolean := False;
      On_Road : Boolean := True;
      Lift       : Float := 0.0;   --  body height above the road (kerbs)
      Lift_Speed : Float := 0.0;
   end record;

   procedure Update (S : in out State; C : Controls; Dt : Float);
   --  Advance physics and resolve collisions with the world

   function Forward (S : State) return Math3D.Vec3;
   function Model_Matrix (S : State) return Math3D.Mat4;

   procedure Create_Mesh;
   --  Build the GPU mesh (GL context must be current)

   procedure Draw;
   --  Draw the mesh; the caller sets the model matrix uniform

end Car;
