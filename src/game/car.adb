--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics.Elementary_Functions;

with Meshes;
with Terrain;
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
      X : constant Float := S.X + Cos (S.Heading) * Side + Sin (S.Heading) * Along;
      Z : constant Float := S.Z + Sin (S.Heading) * Side - Cos (S.Heading) * Along;
   begin
      return (X, Terrain.Height (X, Z) + S.Lift, Z);
   end Wheel_At;

   function Rear_Wheel (S : State; Right : Boolean) return Vec3 is
     (Wheel_At (S, (if Right then 0.82 else -0.82), -1.3));
   function Front_Wheel (S : State; Right : Boolean) return Vec3 is
     (Wheel_At (S, (if Right then 0.82 else -0.82), 1.35));

   function Model_Matrix (S : State) return Mat4 is
     (Translation ((S.X, S.Ground + S.Lift, S.Z)) * Rotation_Y (-S.Heading)
      * Rotation_X (S.Pitch) * Rotation_Z (S.Roll));

   --  How the ground lies under the car: height, pitch, roll, and the grade
   --  along the heading (rise per metre)
   procedure Settle (S : in out State; Grade : out Float) is
      FX : constant Float := Sin (S.Heading);
      FZ : constant Float := -Cos (S.Heading);
      Front : constant Float := Terrain.Height (S.X + 1.4 * FX, S.Z + 1.4 * FZ);
      Back  : constant Float := Terrain.Height (S.X - 1.4 * FX, S.Z - 1.4 * FZ);
      Right : constant Float := Terrain.Height (S.X - 0.8 * FZ, S.Z + 0.8 * FX);
      Left  : constant Float := Terrain.Height (S.X + 0.8 * FZ, S.Z - 0.8 * FX);
   begin
      Grade := (Front - Back) / 2.8;
      S.Ground := Terrain.Height (S.X, S.Z);
      S.Pitch := Arctan (Grade);
      S.Roll := Arctan ((Right - Left) / 1.6);
   end Settle;

   function On_Ground (X, Z, Heading : Float) return State is
      S : State := (X => X, Z => Z, Heading => Heading, others => <>);
      Grade : Float;
   begin
      Settle (S, Grade);
      return S;
   end On_Ground;

   Kerb_Height : constant := 0.14;

   function Circles (Long : Boolean) return Float_Array is
     (if Long then (5.0, 1.7, -1.7, -5.0) else (Circle_Offset, -Circle_Offset));

   Current_Model : Model_Kind := Modern;   --  the player's

   --  From the front wheels to the back (the bus: long, it turns wide)
   function Base_Of return Float is (if Current_Model = Bus then 6.2 else Wheel_Base);

   function Lean (S : State) return Float is
      --  the sideways pull of the turn against gravity
      Side_G : constant Float := S.Speed * S.Speed * Tan (S.Steer) / (Base_Of * 9.81);
   begin
      return Float'Max (-0.6, Float'Min (0.6, Arctan (Side_G)));
   end Lean;

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
        (if C.Analog then C.Throttle_Pedal elsif C.Throttle then 1.0 else 0.0) * C.Power;
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
         --  a car just put down (landing, reset, a jump) takes the gear the
         --  lever is already in; only moving the lever needs the clutch
         if C.Gear /= S.Gear then
            if C.Gear = 0 or else not C.Need_Clutch or else Clutch > 0.6
              or else S.Last_Lever = 99
            then
               S.Gear := C.Gear;
            else
               S.Gear := 0;
               S.Grinding := True;
            end if;
         end if;
         S.Last_Lever := C.Gear;
      else
         --  Automatic: drive, or reverse with the shifter in R, or by
         --  holding the brake when stopped (keyboard)
         if C.Analog and then C.Gear = -1 then
            S.Gear := -1;
         elsif S.Gear = -1 and then not (C.Analog and then C.Gear = -1)
           and then Throttle_In > 0.02 and then S.Speed > -0.5
         then
            S.Gear := 1;
         --  (the brake key always works, whatever the wheel's shifter says)
         elsif S.Gear >= 0 and then Brake_In > 0.02 and then Throttle_In < 0.02
           and then S.Speed < 0.3
           and then (C.Brake or else not (C.Analog and then C.Gear > 0))
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
      --  Hills: gravity pulls the car down the slope (the brakes hold it)
      declare
         Grade : Float;
         Holding : constant Boolean :=
           C.Handbrake or else (if C.Analog then C.Brake_Pedal > 0.3 else C.Brake);
      begin
         Settle (S, Grade);
         if not (Holding and then abs S.Speed < 0.5) then
            S.Speed := S.Speed - 9.81 * Grade / Sqrt (1.0 + Grade * Grade) * Dt;
         end if;
      end;
      if C.Handbrake then
         Approach (S.Speed, 0.0, 9.0 * Dt);
         if abs S.Speed > 3.0 then
            S.Skid := 1.0;
         end if;
      end if;
      S.Speed := S.Speed - S.Speed * abs S.Speed * 0.0006 * Dt;  --  air drag
      if Current_Model = Scooter then
         --  a 50 cc scooter: 55 km/h at most, flat out
         S.Speed := Float'Max (-3.0, Float'Min (15.5, S.Speed));
      elsif Current_Model = Bus then
         --  a town bus: 50 km/h is plenty
         S.Speed := Float'Max (-3.0, Float'Min (14.0, S.Speed));
      elsif Current_Model = Velib then
         --  a heavy town bike: 23 km/h pedalling hard, and walking it back
         S.Speed := Float'Max (-1.5, Float'Min (6.4, S.Speed));
      end if;

      --  Steering: less lock at speed, returns to centre when released;
      --  a wheel turns the front wheels directly (900 degrees lock to
      --  lock is a ratio of about 14:1, like a real car)
      if C.Analog then
         Steer_Target := (C.Steering + C.Pull) * Max_Steer;
         Approach (S.Steer, Steer_Target, 8.0 * Dt);
      else
         if C.Left then
            Steer_Target := -Max_Steer / Speed_Factor;
         elsif C.Right then
            Steer_Target := Max_Steer / Speed_Factor;
         end if;
         Steer_Target := Steer_Target + C.Pull * Max_Steer;
         Approach (S.Steer, Steer_Target, 2.5 * Dt);
      end if;

      --  Bicycle model; the tyres hold the car in a turn only up to their
      --  grip, beyond that it slides wide (and squeals).  Spinning rear
      --  wheels and the handbrake let the tail come round.
      declare
         Yaw   : Float := S.Speed / Base_Of * Tan (S.Steer)
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

      --  Collision: two circles (front and rear; four along the bus)
      --  pushed out of edges
      S.Bumped := False;
      for Offset of Circles (Current_Model = Bus) loop
         declare
            Two_Wheels : constant Boolean := Current_Model in Scooter | Velib;
            Along : constant Float := (if Two_Wheels then 0.45 * Offset else Offset);
            Radius : constant Float := (if Two_Wheels then 0.45 elsif Current_Model = Bus then 1.25
                                        else Body_Radius);
            FX : constant Float := Sin (S.Heading) * Along;
            FZ : constant Float := -Cos (S.Heading) * Along;
            CX : Float := S.X + FX;
            CZ : Float := S.Z + FZ;
            Hit : Boolean;
            NX, NZ : Float;
         begin
            World.Collide (CX, CZ, Radius, Hit, NX, NZ);
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

   Models : array (Model_Kind) of Meshes.Mesh;

   procedure Create_Mesh is
      use Meshes;
   begin
      --  A plain modern car (front is -Z)
      Start;
      Box (-0.88, 0.88, 0.32, 0.95, -2.15, 2.1, Mat_Paint,
           Top_Inset_X => 0.03, Top_Inset_Front => 0.1, Top_Inset_Back => 0.05);
      Box (-0.80, 0.80, 0.95, 1.42, -0.9, 1.15, Mat_Paint,
           Top_Inset_X => 0.12, Top_Inset_Front => 0.55, Top_Inset_Back => 0.3,
           Side_Mat => Mat_Glass);
      for WX of Float_Array'(-0.82, 0.82) loop
         for WZ of Float_Array'(-1.35, 1.3) loop
            Box (WX - 0.14, WX + 0.14, 0.0, 0.66, WZ - 0.33, WZ + 0.33, Mat_Tyre);
         end loop;
      end loop;
      Box (-0.78, -0.45, 0.68, 0.82, -2.17, -2.1, Mat_Headlight);
      Box (0.45, 0.78, 0.68, 0.82, -2.17, -2.1, Mat_Headlight);
      Box (-0.82, -0.5, 0.72, 0.86, 2.06, 2.12, Mat_Taillight);
      Box (0.5, 0.82, 0.72, 0.86, 2.06, 2.12, Mat_Taillight);
      Finish (Models (Modern));

      --  The 2CV: tall and narrow, a rounded canvas roof, a ribbed bonnet
      --  sloping down to the front, separate wings and round lamps
      Start;
      Box (-0.68, 0.68, 0.32, 0.92, -0.95, 1.75, Mat_Paint,
           Top_Inset_Back => 0.25);                                     --  cabin and boot
      Box (-0.66, 0.66, 0.92, 1.62, -0.85, 1.3, Mat_Paint,
           Top_Inset_X => 0.2, Top_Inset_Front => 0.35, Top_Inset_Back => 0.7,
           Side_Mat => Mat_Glass);                                      --  tall round roof
      Box (-0.5, 0.5, 0.42, 0.9, -1.85, -0.95, Mat_Paint,
           Top_Inset_X => 0.08, Top_Inset_Front => 0.5);                --  bonnet
      Box (-0.42, 0.42, 0.36, 0.62, -1.92, -1.82, Mat_Tyre);            --  grille
      for Side of Float_Array'(-1.0, 1.0) loop
         Box (Side * 0.74 - 0.13, Side * 0.74 + 0.13, 0.32, 0.72, -1.75, -0.92, Mat_Paint,
              Top_Inset_Front => 0.35, Top_Inset_X => 0.03);            --  front wings
         Box (Side * 0.72 - 0.1, Side * 0.72 + 0.1, 0.32, 0.7, 0.95, 1.7, Mat_Paint,
              Top_Inset_Back => 0.15);                                  --  rear wings
         Box (Side * 0.55 - 0.1, Side * 0.55 + 0.1, 0.78, 0.96, -1.6, -1.46,
              Mat_Headlight);                                           --  round lamps
         Box (Side * 0.66 - 0.06, Side * 0.66 + 0.06, 0.6, 0.72, 1.7, 1.74, Mat_Taillight);
      end loop;
      for WX of Float_Array'(-0.7, 0.7) loop
         for WZ of Float_Array'(-1.3, 1.25) loop
            Box (WX - 0.09, WX + 0.09, 0.0, 0.64, WZ - 0.3, WZ + 0.3, Mat_Tyre);
         end loop;
      end loop;
      Finish (Models (Deux_Chevaux));

      --  The DS: long and low, a nose like a shark, a roof tapering to the
      --  back with the indicator "trumpets", half-covered rear wheels
      Start;
      Box (-0.88, 0.88, 0.3, 0.82, -1.7, 1.9, Mat_Paint,
           Top_Inset_X => 0.04);                                        --  body
      Box (-0.84, 0.84, 0.26, 0.74, -2.5, -1.7, Mat_Paint,
           Top_Inset_X => 0.1, Top_Inset_Front => 0.6);                 --  the nose
      Box (-0.82, 0.82, 0.3, 0.8, 1.9, 2.45, Mat_Paint,
           Top_Inset_X => 0.08, Top_Inset_Back => 0.25);                --  the tail
      Box (-0.8, 0.8, 0.82, 1.4, -0.95, 1.75, Mat_Paint,
           Top_Inset_X => 0.13, Top_Inset_Front => 0.5, Top_Inset_Back => 0.85,
           Side_Mat => Mat_Glass);                                      --  cabin
      for Side of Float_Array'(-1.0, 1.0) loop
         Box (Side * 0.62 - 0.1, Side * 0.62 + 0.1, 1.27, 1.34, 1.35, 1.5,
              Mat_Taillight);                                           --  trumpets
         Box (Side * 0.66 - 0.12, Side * 0.66 + 0.12, 0.55, 0.68, -2.45, -2.36,
              Mat_Headlight);
         Box (Side * 0.7 - 0.1, Side * 0.7 + 0.1, 0.55, 0.65, 2.42, 2.46, Mat_Taillight);
      end loop;
      for WX of Float_Array'(-0.82, 0.82) loop
         Box (WX - 0.12, WX + 0.12, 0.0, 0.66, -1.75, -1.1, Mat_Tyre);   --  front
         Box (WX - 0.08, WX + 0.08, 0.0, 0.42, 1.0, 1.6, Mat_Tyre);      --  rear, behind the skirts
      end loop;
      Finish (Models (DS));

      --  The Renault 4: a small box on wheels, upright, the roof flat and
      --  long, the tailgate straight, a broad flat grille between round lamps
      Start;
      Box (-0.76, 0.76, 0.32, 0.88, -1.6, 1.75, Mat_Paint, Top_Inset_X => 0.03);          --  body
      Box (-0.74, 0.74, 0.32, 0.8, -1.95, -1.6, Mat_Paint, Top_Inset_Front => 0.12);      --  the short bonnet's nose
      Box (-0.72, 0.72, 0.88, 1.52, -0.75, 1.75, Mat_Paint,
           Top_Inset_X => 0.07, Top_Inset_Front => 0.3, Side_Mat => Mat_Glass);           --  tall glasshouse
      Box (-0.6, 0.6, 0.45, 0.68, -1.97, -1.92, Mat_Tyre);                               --  the grille
      for Side of Float_Array'(-1.0, 1.0) loop
         Box (Side * 0.55 - 0.09, Side * 0.55 + 0.09, 0.5, 0.66, -1.98, -1.94, Mat_Headlight);
         Box (Side * 0.68 - 0.05, Side * 0.68 + 0.05, 0.62, 0.8, 1.75, 1.78, Mat_Taillight);
      end loop;
      Box (-0.8, 0.8, 0.32, 0.42, -2.0, -1.9, Mat_Tyre);                                --  bumpers
      Box (-0.8, 0.8, 0.32, 0.42, 1.75, 1.85, Mat_Tyre);
      for WX of Float_Array'(-0.7, 0.7) loop
         for WZ of Float_Array'(-1.25, 1.2) loop
            Box (WX - 0.1, WX + 0.1, 0.0, 0.6, WZ - 0.28, WZ + 0.28, Mat_Tyre);
         end loop;
      end loop;
      Finish (Models (R4));

      --  The baker's scooter: a step-through with its leg shield, the
      --  rider in a dark jacket and a helmet in the paint, and on the rack
      --  behind a wooden crate full of baguettes standing up
      Start;
      Box (-0.06, 0.06, 0.0, 0.48, -0.9, -0.42, Mat_Tyre);              --  wheels
      Box (-0.07, 0.07, 0.0, 0.48, 0.42, 0.9, Mat_Tyre);
      Box (-0.19, 0.19, 0.22, 0.34, -0.58, 0.32, Mat_Paint);             --  floorboard
      Box (-0.23, 0.23, 0.3, 0.8, 0.1, 0.88, Mat_Paint,
           Top_Inset_X => 0.04, Top_Inset_Back => 0.15);                  --  rear body
      Box (-0.22, 0.22, 0.3, 1.02, -0.7, -0.55, Mat_Paint, Top_Inset_X => 0.05);   --  leg shield
      Box (-0.04, 0.04, 0.95, 1.14, -0.66, -0.58, Mat_Tyre);             --  steering
      Box (-0.36, 0.36, 1.1, 1.16, -0.64, -0.57, Mat_Tyre);              --  handlebar
      Box (-0.08, 0.08, 1.0, 1.12, -0.72, -0.66, Mat_Headlight);
      Box (-0.07, 0.07, 0.62, 0.7, 0.88, 0.91, Mat_Taillight);
      Box (-0.18, 0.18, 0.8, 0.88, 0.0, 0.6, Mat_Tyre);                  --  seat
      Box (-0.15, 0.15, 0.34, 0.88, -0.32, -0.12, Mat_Tyre);             --  lower legs
      Box (-0.18, 0.18, 0.88, 1.05, -0.45, 0.1, Mat_Tyre);               --  thighs
      Box (-0.21, 0.21, 1.03, 1.62, -0.15, 0.25, Mat_Tyre,
           Top_Inset_X => 0.03);                                          --  jacket
      Box (-0.15, 0.15, 1.62, 1.94, -0.12, 0.2, Mat_Paint, Top_Inset_X => 0.03,
           Top_Inset_Front => 0.04, Top_Inset_Back => 0.04);              --  helmet
      Box (-0.12, 0.12, 1.7, 1.83, -0.14, -0.11, Mat_Glass);             --  visor
      for Side of Float_Array'(-1.0, 1.0) loop
         Box (Side * 0.28 - 0.05, Side * 0.28 + 0.05, 1.1, 1.52, -0.6, 0.0, Mat_Tyre);   --  arms
      end loop;
      Box (-0.3, 0.3, 0.86, 0.9, 0.55, 1.15, Mat_Tyre);                  --  the rack
      Box (-0.3, 0.3, 0.9, 1.3, 0.55, 1.15, 60.0);                       --  the crate
      for I in 0 .. 3 loop
         for J in 0 .. 2 loop
            declare
               X : constant Float := -0.21 + 0.14 * Float (I);
               Z : constant Float := 0.66 + 0.19 * Float (J);
               H : constant Float := 1.62 + 0.06 * Float ((I * 2 + J) mod 3);
            begin
               Box (X - 0.035, X + 0.035, 1.25, H, Z - 0.035, Z + 0.035, 89.0);   --  baguettes
            end;
         end loop;
      end loop;
      Finish (Models (Scooter));

      --  The Vélib': the mint-green step-through frame, the basket in
      --  front, and you on it in your jacket (paint, matt), trousers and
      --  face in the walkers' colours (extra colours)
      Start;
      Box (-0.03, 0.03, 0.0, 0.66, -0.88, -0.22, Mat_Tyre);             --  wheels
      Box (-0.03, 0.03, 0.0, 0.66, 0.22, 0.88, Mat_Tyre);
      Box (-0.04, 0.04, 0.3, 0.42, -0.55, 0.55, 87.0);                  --  the low frame
      Box (-0.04, 0.04, 0.36, 0.95, 0.1, 0.22, 87.0);                   --  the seat tube
      Box (-0.04, 0.04, 0.35, 1.08, -0.62, -0.52, 87.0);                --  the head tube
      Box (-0.04, 0.04, 0.3, 0.7, 0.45, 0.6, 87.0);                     --  the rear fork
      Box (-0.3, 0.3, 1.04, 1.08, -0.5, -0.44, Mat_Tyre);              --  the handlebar
      Box (-0.17, 0.17, 0.78, 1.02, -0.9, -0.6, 87.0);                  --  the basket
      Box (-0.13, 0.13, 0.94, 1.0, 0.0, 0.3, Mat_Tyre);                 --  the saddle
      Box (-0.1, 0.1, 0.3, 0.42, 0.62, 0.8, 87.0);                      --  the rear light
      Box (-0.04, 0.04, 0.33, 0.39, 0.8, 0.82, Mat_Taillight);
      Box (-0.04, 0.04, 0.85, 0.95, -0.92, -0.9, Mat_Headlight);
      Box (-0.17, 0.17, 0.95, 1.13, -0.3, 0.2, Mat_Trousers);           --  thighs
      for Side of Float_Array'(-1.0, 1.0) loop
         Box (Side * 0.11 - 0.06, Side * 0.11 + 0.06, 0.25, 1.0, -0.38, -0.24, Mat_Trousers);   --  shins
         Box (Side * 0.11 - 0.06, Side * 0.11 + 0.06, 0.2, 0.28, -0.46, -0.24, Mat_Tyre);       --  shoes
      end loop;
      Box (-0.21, 0.21, 1.1, 1.68, -0.12, 0.24, Mat_Cloth, Top_Inset_X => 0.03,
           Top_Inset_Front => 0.06);                                    --  the jacket
      for Side of Float_Array'(-1.0, 1.0) loop
         Box (Side * 0.26 - 0.05, Side * 0.26 + 0.05, 1.08, 1.6, -0.48, 0.05, Mat_Cloth);   --  arms
      end loop;
      Box (-0.07, 0.07, 1.66, 1.76, -0.02, 0.1, Mat_Skin);              --  neck
      Box (-0.12, 0.12, 1.74, 2.0, -0.1, 0.14, Mat_Skin, Top_Inset_X => 0.02);   --  head
      Box (-0.13, 0.13, 1.92, 2.04, -0.08, 0.16, Mat_Tyre, Top_Inset_X => 0.03);  --  hair
      Finish (Models (Velib));

      --  The night bus: twelve metres long, low-floor, a band of windows
      --  lit from inside (glass), the destination sign over the
      --  windscreen, three doors on the right, in the paint
      Start;
      Box (-1.27, 1.27, 0.3, 3.0, -6.0, 6.0, Mat_Paint, Top_Inset_X => 0.05,
           Side_Mat => Mat_Paint);                                        --  body
      Box (-1.29, 1.29, 1.15, 2.55, -5.2, 5.6, 61.0);                   --  the windows, lit inside
      Box (-1.22, 1.22, 0.9, 2.65, -6.04, -5.98, Mat_Glass);             --  windscreen
      Box (-1.0, 1.0, 2.68, 2.92, -6.06, -6.0, Mat_Headlight);           --  destination sign
      Box (-1.1, 1.1, 1.6, 2.6, 5.98, 6.03, Mat_Glass);                  --  rear window
      for D of Float_Array'(-4.6, 0.2, 4.2) loop
         Box (1.27, 1.31, 0.35, 2.6, D - 0.6, D + 0.6, Mat_Glass);      --  the doors (right)
      end loop;
      for Side of Float_Array'(-1.0, 1.0) loop
         Box (Side * 0.95 - 0.18, Side * 0.95 + 0.18, 0.45, 0.62, -6.05, -6.0, Mat_Headlight);
         Box (Side * 1.05 - 0.1, Side * 1.05 + 0.1, 0.7, 1.1, 6.0, 6.05, Mat_Taillight);
         for WZ of Float_Array'(-3.6, 2.6) loop
            Box (Side * 1.1 - 0.16, Side * 1.1 + 0.16, 0.0, 0.95, WZ - 0.5, WZ + 0.5, Mat_Tyre);
         end loop;
      end loop;
      Box (-1.27, 1.27, 0.25, 0.45, -6.06, 6.06, Mat_Tyre);              --  the skirt
      Finish (Models (Bus));
   end Create_Mesh;

   procedure Set_Player_Model (M : Model_Kind) is
   begin
      Current_Model := M;
   end Set_Player_Model;

   function Player_Model return Model_Kind is (Current_Model);

   procedure Draw is
   begin
      Meshes.Draw (Models (Current_Model));
   end Draw;

   procedure Draw_Model (M : Model_Kind) is
   begin
      Meshes.Draw (Models (M));
   end Draw_Model;

end Car;
