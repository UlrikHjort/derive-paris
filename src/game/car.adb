--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics.Elementary_Functions;

with Meshes;
with World;

package body Car is

   use Ada.Numerics.Elementary_Functions;
   use Math3D;

   type Float_Array is array (Positive range <>) of Float;

   Wheel_Base    : constant := 2.6;
   Max_Steer     : constant := 0.55;
   Brake_Decel   : constant := 14.0;
   Body_Radius   : constant := 1.0;    --  collision circles along the car
   Circle_Offset : constant := 1.15;

   function Forward (S : State) return Vec3 is
     ((Sin (S.Heading), 0.0, -Cos (S.Heading)));

   function Wheel_At (S : State; Side, Along : Float) return Vec3 is
     ((S.X + Cos (S.Heading) * Side + Sin (S.Heading) * Along,
       S.Lift,
       S.Z + Sin (S.Heading) * Side - Cos (S.Heading) * Along));

   function Rear_Wheel (S : State; Right : Boolean) return Vec3 is
     (Wheel_At (S, (if Right then 0.82 else -0.82), -1.3));
   function Front_Wheel (S : State; Right : Boolean) return Vec3 is
     (Wheel_At (S, (if Right then 0.82 else -0.82), 1.35));

   function Model_Matrix (S : State) return Mat4 is
     (Translation ((S.X, S.Lift, S.Z)) * Rotation_Y (-S.Heading));

   Kerb_Height : constant := 0.14;

   procedure Approach (V : in out Float; Target, Rate : Float) is
   begin
      if V < Target then
         V := Float'Min (Target, V + Rate);
      else
         V := Float'Max (Target, V - Rate);
      end if;
   end Approach;

   ---------------------------------------------------------------------------
   --  Engine and gearbox: six gears and reverse, an engine with a torque
   --  curve, and either a clutch and the shifter (manual) or a torque
   --  converter that changes gear by itself (automatic).  Forgiving: the
   --  engine does not stall, and in gear (manual) the car creeps at idle.
   --
   --  The tyres only grip so much (less in the rain).  Dropping the clutch
   --  at high revs, or too much power on a wet road, spins the driven
   --  (rear) wheels; braking very hard locks them and fast cornering
   --  slides them.
   ---------------------------------------------------------------------------

   Idle_Rpm : constant := 850.0;
   Red_Line : constant := 6500.0;

   --  Speed (km/h) at the red line in each gear; reverse like first
   Gear_Top : constant array (-1 .. 6) of Float :=
     (38.0, 1.0, 45.0, 75.0, 108.0, 140.0, 170.0, 200.0);
   --  Acceleration (m/s^2) at peak torque and full throttle
   Gear_Pull : constant array (-1 .. 6) of Float :=
     (4.5, 0.0, 5.5, 3.7, 2.7, 2.05, 1.65, 1.35);

   function Torque (Rpm : Float) return Float is
     (Float'Max (0.45, 1.0 - ((Rpm - 4000.0) / 4500.0) ** 2));

   --  Engine rpm per m/s of wheel speed in a gear
   function Ratio (G : Integer) return Float is (Red_Line * 3.6 / Gear_Top (G));

   function Grip (C : Controls) return Float is
     (Float'Max (2.2, 7.5 - 3.5 * C.Wet - 4.5 * C.Snow));

   procedure Drive (S : in out State; C : Controls; Dt : Float) is
      Throttle_In : constant Float :=
        (if C.Analog then C.Throttle_Pedal elsif C.Throttle then 1.0 else 0.0);
      Brake_In    : constant Float :=
        (if C.Analog then C.Brake_Pedal elsif C.Brake then 1.0 else 0.0);
      Throttle, Brake : Float;
      Clutch   : constant Float := (if C.Analog and then C.Manual then C.Clutch_Pedal else 0.0);
      --  Clutch engagement: the bite point is in the middle of the travel
      Engage   : Float := Float'Max (0.0, Float'Min (1.0, (0.8 - Clutch) / 0.5));
      Free_Rpm : Float;
      Limit    : constant Float := Grip (C);
   begin
      S.Grinding := False;
      if C.Manual then
         --  Gear changes with the shifter
         Throttle := Throttle_In;
         Brake := Brake_In;
         if C.Gear /= S.Gear then
            if C.Gear = 0 or else not C.Need_Clutch or else Clutch > 0.6 then
               S.Gear := C.Gear;
            else
               S.Gear := 0;
               S.Grinding := True;
            end if;
         end if;
      else
         --  Automatic: drive, or reverse with the shifter in R, or by
         --  holding the brake when stopped (keyboard)
         if C.Analog and then C.Gear = -1 then
            S.Gear := -1;
         elsif S.Gear = -1 and then not (C.Analog and then C.Gear = -1)
           and then Throttle_In > 0.02 and then S.Speed > -0.5
         then
            S.Gear := 1;
         elsif S.Gear >= 0 and then Brake_In > 0.02 and then Throttle_In < 0.02
           and then S.Speed < 0.3 and then not (C.Analog and then C.Gear > 0)
         then
            S.Gear := -1;
         elsif S.Gear = 0 then
            S.Gear := 1;
         end if;
         if S.Gear = -1 and then not (C.Analog and then C.Gear = -1) then
            --  reversing on the keys: brake drives backwards, throttle brakes
            Throttle := Brake_In;
            Brake := Throttle_In;
         else
            Throttle := Throttle_In;
            Brake := Brake_In;
         end if;
         --  change up and down by the revs, later with more throttle
         S.Shift_Wait := Float'Max (0.0, S.Shift_Wait - Dt);
         if S.Gear >= 1 and then S.Shift_Wait = 0.0 then
            declare
               R : constant Float := Float'Max (0.0, S.Speed) * Ratio (S.Gear);
            begin
               if S.Gear < 6 and then Brake < 0.1 and then R > 2500.0 + 3300.0 * Throttle then
                  S.Gear := S.Gear + 1;
                  S.Shift_Wait := 0.35;
               elsif S.Gear > 1 and then R * Ratio (S.Gear - 1) / Ratio (S.Gear)
                   < 2300.0 + 3000.0 * Throttle
                 and then R < 1200.0 + 1800.0 * Throttle
               then
                  S.Gear := S.Gear - 1;
                  S.Shift_Wait := 0.35;
               end if;
            end;
         end if;
         --  Throttle against the brake at a standstill: the engine is
         --  held at the converter's stall speed; let go of the brake and
         --  the wheels spin
         if Brake > 0.3 and then Throttle > 0.7 and then abs S.Speed < 1.0 then
            S.Power_Brake := True;
         elsif S.Power_Brake and then Brake < 0.1 and then Throttle > 0.7 then
            S.Spin := S.Spin + 7.0;
            S.Power_Brake := False;
         elsif Throttle < 0.5 then
            S.Power_Brake := False;
         end if;
      end if;
      if S.Gear = 0 then
         Engage := 0.0;
      end if;

      --  The engine spinning freely (clutch pressed or neutral)
      Free_Rpm := Idle_Rpm + Throttle * (Red_Line + 300.0 - Idle_Rpm);

      if Engage > 0.0 then
         declare
            Dir       : constant Float := (if S.Gear < 0 then -1.0 else 1.0);
            Road_Rpm  : constant Float := Float'Max (0.0, Dir * S.Speed) * Ratio (S.Gear);
            Wheel_Rpm : Float;
            --  The idle governor gives some torque when the engine is held
            --  down near idle, so the car creeps in a low gear
            Idle_Help : constant Float :=
              (if C.Manual
               then Float'Max (0.0, Float'Min (0.25, (1100.0 - Road_Rpm) / 1200.0))
               else 0.0);
            Gas       : constant Float := Float'Max (Throttle, Idle_Help);
            Rpm, Pull : Float;
            First     : constant Boolean := S.Gear = 1;   --  only first gear spins
         begin
            --  Dropping the clutch with the engine revving: the difference
            --  goes into the wheels, which spin
            if not First then
               S.Spin := Float'Max (0.0, S.Spin - 25.0 * Dt);
            end if;
            if C.Manual and then First and then Engage > S.Engaged
              and then S.Rpm > Road_Rpm + 1500.0
            then
               S.Spin := S.Spin + (S.Rpm - Road_Rpm) / Ratio (S.Gear)
                 * (Engage - S.Engaged) * 0.9;
            end if;
            if S.Power_Brake then
               S.Spin := 0.0;
            end if;
            Wheel_Rpm := Road_Rpm + S.Spin * Ratio (S.Gear);
            Rpm := Engage * Float'Max (Wheel_Rpm, Idle_Rpm * 0.9) + (1.0 - Engage) * Free_Rpm;
            if not C.Manual then
               --  torque converter: the engine runs ahead of the wheels
               Rpm := Float'Max (Rpm, Idle_Rpm + Throttle
                                   * (if S.Power_Brake then 2600.0
                                      else Float'Max (0.0, 2200.0 - Road_Rpm)));
            end if;
            Pull := Gas * Gear_Pull (S.Gear) * Torque (Rpm) * Engage;
            if Wheel_Rpm > Red_Line + 150.0 then
               Pull := 0.0;   --  rev limiter
            end if;

            if First and then (S.Spin > 0.0 or else Pull > Limit) then
               --  Wheelspin: the tyres push with what grip they have; the
               --  wheels keep spinning as long as the engine overpowers them
               if Engage > 0.3 then
                  S.Spin := S.Spin + (Pull * 2.2 - Limit) * 3.0 * Dt;
               else
                  S.Spin := S.Spin - 25.0 * Dt;
               end if;
               S.Spin := Float'Max (0.0, Float'Min
                 (S.Spin, (Red_Line + 100.0) / Ratio (S.Gear) - Float'Max (0.0, Dir * S.Speed)));
               if S.Spin > 0.05 and then not S.Power_Brake then
                  S.Speed := S.Speed + Dir * Limit * 0.8 * Dt;
               elsif not S.Power_Brake then
                  S.Speed := S.Speed + Dir * Pull * Dt;
               end if;
            else
               --  Engine braking with the throttle closed
               Pull := Pull - (1.0 - Gas) * Engage * Gear_Pull (S.Gear) * 0.22
                 * Road_Rpm / Red_Line;
               if not S.Power_Brake then
                  S.Speed := S.Speed + Dir * Pull * Dt;
               end if;
            end if;
            Approach (S.Rpm, Float'Min (Red_Line + 200.0, Rpm), 9000.0 * Dt);
         end;
      else
         S.Spin := Float'Max (0.0, S.Spin - 25.0 * Dt);
         Approach (S.Rpm, Free_Rpm, (if Free_Rpm > S.Rpm then 7000.0 else 3500.0) * Dt);
      end if;
      S.Engaged := Engage;

      if Brake > 0.02 then
         Approach (S.Speed, 0.0, Brake_Decel * Brake * Dt);
         --  no ABS: stamp on the brake at speed and the tyres lock
         if Brake > 0.85 and then abs S.Speed > 5.0 then
            S.Skid := Float'Max (S.Skid, 1.0);
         end if;
      end if;
      Approach (S.Speed, 0.0, 0.25 * Dt);   --  rolling resistance
   end Drive;

   procedure Update (S : in out State; C : Controls; Dt : Float) is
      Was_On_Road  : constant Boolean := S.On_Road;
      Steer_Target : Float := 0.0;
      Speed_Factor : constant Float := 1.0 + abs S.Speed / 10.0;
   begin
      --  Longitudinal
      S.Skid := 0.0;
      Drive (S, C, Dt);
      if C.Handbrake then
         Approach (S.Speed, 0.0, 9.0 * Dt);
         if abs S.Speed > 3.0 then
            S.Skid := 1.0;
         end if;
      end if;
      S.Speed := S.Speed - S.Speed * abs S.Speed * 0.0006 * Dt;  --  air drag

      --  Steering: less lock at speed, returns to centre when released;
      --  a wheel turns the front wheels directly (900 degrees lock to
      --  lock is a ratio of about 14:1, like a real car)
      if C.Analog then
         Steer_Target := C.Steering * Max_Steer;
         Approach (S.Steer, Steer_Target, 8.0 * Dt);
      else
         if C.Left then
            Steer_Target := -Max_Steer / Speed_Factor;
         elsif C.Right then
            Steer_Target := Max_Steer / Speed_Factor;
         end if;
         Approach (S.Steer, Steer_Target, 2.5 * Dt);
      end if;

      --  Bicycle model; the tyres hold the car in a turn only up to their
      --  grip, beyond that it slides wide (and squeals).  Spinning rear
      --  wheels and the handbrake let the tail come round.
      declare
         Yaw   : Float := S.Speed / Wheel_Base * Tan (S.Steer)
           * (if C.Handbrake then 1.4 elsif S.Spin > 1.0 then 1.25 else 1.0);
         Lat   : constant Float := abs (Yaw * S.Speed);
         Most  : constant Float := Grip (C) * 1.15;
      begin
         if Lat > Most and then not C.Handbrake then
            S.Skid := Float'Max (S.Skid, Float'Min (1.0, (Lat - Most) / 3.0 + 0.3));
            Yaw := Yaw * (Most + 0.35 * (Lat - Most)) / Lat;
         end if;
         S.Heading := S.Heading + Yaw * Dt;
      end;
      S.X := S.X + Sin (S.Heading) * S.Speed * Dt;
      S.Z := S.Z - Cos (S.Heading) * S.Speed * Dt;

      --  Collision: two circles (front and rear) pushed out of edges
      S.Bumped := False;
      for Offset of Float_Array'(Circle_Offset, -Circle_Offset) loop
         declare
            FX : constant Float := Sin (S.Heading) * Offset;
            FZ : constant Float := -Cos (S.Heading) * Offset;
            CX : Float := S.X + FX;
            CZ : Float := S.Z + FZ;
            Hit : Boolean;
            NX, NZ : Float;
         begin
            World.Collide (CX, CZ, Body_Radius, Hit, NX, NZ);
            if Hit then
               S.X := CX - FX;
               S.Z := CZ - FZ;
               S.Bumped := True;
               S.Hit_NX := NX;
               S.Hit_NZ := NZ;
               --  Remove the velocity component going into the wall
               declare
                  VX : constant Float := Sin (S.Heading) * S.Speed;
                  VZ : constant Float := -Cos (S.Heading) * S.Speed;
                  VN : constant Float := VX * NX + VZ * NZ;
               begin
                  if VN < 0.0 then
                     S.Speed := S.Speed * (1.0 - 0.9 * abs VN / Float'Max (abs S.Speed, 0.01));
                  end if;
               end;
            end if;
         end;
      end loop;

      --  Kerbs: the body rides 14 cm higher on the sidewalk; climbing the
      --  kerb at speed gives a jolt and costs some speed
      S.On_Road := World.On_Road (S.X, S.Z);
      S.Kerb_Jolt := 0.0;
      if Was_On_Road and then not S.On_Road and then abs S.Speed > 2.0 then
         S.Kerb_Jolt := 0.2 + 0.03 * abs S.Speed;
         S.Lift_Speed := S.Lift_Speed + 0.9 + 0.04 * abs S.Speed;
         S.Speed := S.Speed * 0.88;
      elsif not Was_On_Road and then S.On_Road and then abs S.Speed > 2.0 then
         S.Kerb_Jolt := -(0.15 + 0.02 * abs S.Speed);
         S.Lift_Speed := S.Lift_Speed - 0.4;
      end if;
      declare
         Target : constant Float := (if S.On_Road then 0.0 else Kerb_Height);
      begin
         S.Lift_Speed := S.Lift_Speed + ((Target - S.Lift) * 260.0 - S.Lift_Speed * 16.0) * Dt;
         S.Lift := S.Lift + S.Lift_Speed * Dt;
         if S.Lift < 0.0 then
            S.Lift := 0.0;
            S.Lift_Speed := 0.0;
         end if;
      end;
   end Update;

   ---------------------------------------------------------------------------
   --  Mesh
   ---------------------------------------------------------------------------

   Body_Mesh : Meshes.Mesh;

   procedure Create_Mesh is
      use Meshes;
   begin
      Start;
      --  Body (front is -Z)
      Box (-0.88, 0.88, 0.32, 0.95, -2.15, 2.1, Mat_Paint,
           Top_Inset_X => 0.03, Top_Inset_Front => 0.1, Top_Inset_Back => 0.05);
      --  Cabin with glass sides
      Box (-0.80, 0.80, 0.95, 1.42, -0.9, 1.15, Mat_Paint,
           Top_Inset_X => 0.12, Top_Inset_Front => 0.55, Top_Inset_Back => 0.3,
           Side_Mat => Mat_Glass);
      --  Wheels
      for WX of Float_Array'(-0.82, 0.82) loop
         for WZ of Float_Array'(-1.35, 1.3) loop
            Box (WX - 0.14, WX + 0.14, 0.0, 0.66, WZ - 0.33, WZ + 0.33, Mat_Tyre);
         end loop;
      end loop;
      --  Lights
      Box (-0.78, -0.45, 0.68, 0.82, -2.17, -2.1, Mat_Headlight);
      Box (0.45, 0.78, 0.68, 0.82, -2.17, -2.1, Mat_Headlight);
      Box (-0.82, -0.5, 0.72, 0.86, 2.06, 2.12, Mat_Taillight);
      Box (0.5, 0.82, 0.72, 0.86, 2.06, 2.12, Mat_Taillight);
      Finish (Body_Mesh);
   end Create_Mesh;

   procedure Draw is
   begin
      Meshes.Draw (Body_Mesh);
   end Draw;

end Car;
