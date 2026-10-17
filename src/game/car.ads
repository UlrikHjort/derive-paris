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

      --  A racing wheel: pedal and steering amounts instead of the keys
      Analog         : Boolean := False;
      Throttle_Pedal : Float := 0.0;   --  0 .. 1
      Brake_Pedal    : Float := 0.0;
      Clutch_Pedal   : Float := 0.0;
      Steering       : Float := 0.0;   --  -1 .. 1, full lock

      --  Manual gearbox: the shifter position (-1 reverse, 0 neutral);
      --  with Need_Clutch a gear only goes in with the clutch pressed
      Manual      : Boolean := False;
      Gear        : Integer range -1 .. 6 := 0;
      Need_Clutch : Boolean := True;

      Wet : Float := 0.0;   --  0 .. 1: less grip in the rain
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
      Rpm      : Float := 850.0;    --  engine
      Gear     : Integer range -1 .. 6 := 0;   --  engaged gear
      Grinding : Boolean := False;  --  shifter in gear, gear not in
      Kerb_Jolt : Float := 0.0;     --  kerb hit this step (for the wheel)
      Spin     : Float := 0.0;      --  m/s the driven wheels spin faster than the car
      Skid     : Float := 0.0;      --  0 .. 1: tyres sliding (locked, cornering, handbrake)
      Engaged  : Float := 0.0;      --  clutch engagement last step
      Shift_Wait : Float := 0.0;    --  automatic: seconds until the next shift
      Power_Brake : Boolean := False;  --  automatic: throttle against the brake
   end record;

   function Rear_Wheel (S : State; Right : Boolean) return Math3D.Vec3;
   function Front_Wheel (S : State; Right : Boolean) return Math3D.Vec3;
   --  Where the tyres touch the road

   procedure Update (S : in out State; C : Controls; Dt : Float);
   --  Advance physics and resolve collisions with the world

   function Forward (S : State) return Math3D.Vec3;
   function Model_Matrix (S : State) return Math3D.Mat4;

   procedure Create_Mesh;
   --  Build the GPU mesh (GL context must be current)

   procedure Draw;
   --  Draw the mesh; the caller sets the model matrix uniform

end Car;
