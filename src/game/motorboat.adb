--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Environment_Variables;
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;

with Boats;
with River;
with Seasons;
with Terrain;

package body Motorboat is

   use Ada.Numerics.Elementary_Functions;

   Half   : constant := 34.0;   --  how far from the middle of the river it may go
   Top    : constant := 11.0;   --  m/s, some 40 km/h
   Bob    : Float := 0.0;

   procedure Hire_Point (X, Z : out Float) is
   begin
      Boats.Hire_Point (X, Z);
      Z := Z + 1.5;   --  (the mark, as the landing's)
   end Hire_Point;

   function At_Hire (X, Z : Float) return Boolean is
      HX, HZ : Float;
   begin
      Hire_Point (HX, HZ);
      return (X - HX) ** 2 + (Z - HZ) ** 2 < 0.9 ** 2;
   end At_Hire;

   --  The middle of the river nearest (X, Z), its way, and the water's level
   procedure Middle (X, Z : Float; MX, MZ, DX, DZ, Level : out Float) is
   begin
      River.At_Distance (River.Distance_Of (X, Z), MX, MZ, DX, DZ);
      Level := Terrain.Height (MX, MZ) - River.Depth + Seasons.Flood;
   end Middle;

   procedure Launch (S : out Car.State) is
      LX, LZ, MX, MZ, DX, DZ, Level : Float;
   begin
      Boats.Landing (LX, LZ);
      Middle (LX, LZ, MX, MZ, DX, DZ, Level);
      declare
         --  most of the way out from the middle towards the landing
         BX : constant Float := MX + 0.55 * (LX - MX);
         BZ : constant Float := MZ + 0.55 * (LZ - MZ);
      begin
         S := (X => BX, Z => BZ, Heading => Arctan (DX, -DZ), others => <>);
         S.Ground := Terrain.Height (BX, BZ) - River.Depth + Seasons.Flood;
         S.Gear := 1;
      end;
   end Launch;

   function Near_Landing (S : Car.State) return Boolean is
      LX, LZ, MX, MZ, DX, DZ, Level : Float;
   begin
      Boats.Landing (LX, LZ);
      Middle (LX, LZ, MX, MZ, DX, DZ, Level);
      return (S.X - (MX + 0.55 * (LX - MX))) ** 2 + (S.Z - (MZ + 0.55 * (LZ - MZ))) ** 2 < 30.0 ** 2;
   end Near_Landing;

   --  PARIS_BOAT_GO=1: full ahead down the river, keeping to the middle
   --  (testing)
   function Pilot (S : Car.State) return Float is
      MX, MZ, DX, DZ, Level : Float;
   begin
      Middle (S.X, S.Z, MX, MZ, DX, DZ, Level);
      declare
         Want : constant Float := Arctan (DX, -DZ);
         Side : constant Float := (S.X - MX) * (-DZ) + (S.Z - MZ) * DX;
         Err  : Float := Want - S.Heading - 0.02 * Side;
      begin
         while Err > Ada.Numerics.Pi loop
            Err := Err - 2.0 * Ada.Numerics.Pi;
         end loop;
         while Err < -Ada.Numerics.Pi loop
            Err := Err + 2.0 * Ada.Numerics.Pi;
         end loop;
         return Float'Max (-1.0, Float'Min (1.0, 2.0 * Err));
      end;
   end Pilot;

   procedure Step (S : in out Car.State; C : Car.Controls; Dt : Float) is
      Auto : constant Boolean := Ada.Environment_Variables.Exists ("PARIS_BOAT_GO");
      Throttle : constant Float :=
        (if Auto then 1.0 elsif C.Analog then C.Throttle_Pedal elsif C.Throttle then 1.0 else 0.0);
      Brake : constant Float := (if C.Analog then C.Brake_Pedal elsif C.Brake then 1.0 else 0.0);
      Steer : constant Float :=
        (if Auto then Pilot (S)
         elsif C.Analog then C.Steering elsif C.Left then -1.0 elsif C.Right then 1.0 else 0.0);
      MX, MZ, DX, DZ, Level : Float;
   begin
      --  the propeller pushes, the water holds it back; the brake is
      --  the engine in reverse
      S.Speed := S.Speed + (3.0 * Throttle - 3.5 * Brake) * Dt - 0.12 * S.Speed * Dt
        - 0.02 * S.Speed * abs S.Speed * Dt;
      S.Speed := Float'Max (-3.0, Float'Min (Top, S.Speed));
      if Throttle = 0.0 and then Brake = 0.0 and then abs S.Speed < 0.05 then
         S.Speed := 0.0;
      end if;
      --  the rudder: it turns better with way on, a little even at rest
      S.Steer := S.Steer + (Steer * 0.5 - S.Steer) * Float'Min (1.0, 4.0 * Dt);
      S.Heading := S.Heading + S.Steer * (0.25 + 0.75 * Float'Min (1.0, abs S.Speed / 5.0))
        * (if S.Speed < 0.0 then -1.0 else 1.0) * 0.9 * Dt;
      S.X := S.X + Sin (S.Heading) * S.Speed * Dt;
      S.Z := S.Z - Cos (S.Heading) * S.Speed * Dt;

      --  between the quay walls
      S.Bumped := False;
      Middle (S.X, S.Z, MX, MZ, DX, DZ, Level);
      declare
         Side : constant Float := (S.X - MX) * (-DZ) + (S.Z - MZ) * DX;   --  across the river
      begin
         if abs Side > Half then
            S.X := S.X - (Side - (if Side > 0.0 then Half else -Half)) * (-DZ);
            S.Z := S.Z - (Side - (if Side > 0.0 then Half else -Half)) * DX;
            S.Speed := S.Speed * 0.6;
            S.Bumped := True;
         end if;
      end;

      --  on the water (its level where the boat is, as the river's surface
      --  is drawn), the bow up a little with speed, rocking, heeling in a turn
      Bob := Bob + Dt;
      S.Ground := Terrain.Height (S.X, S.Z) - River.Depth + Seasons.Flood;
      S.Lift := 0.0;
      S.Pitch := 0.05 * S.Speed / Top + 0.012 * Sin (Bob * 1.7);
      S.Roll := -0.12 * S.Steer * S.Speed / Top + 0.01 * Sin (Bob * 1.3);
      S.Rpm := 900.0 + 3500.0 * Throttle + 200.0 * abs S.Speed;
   end Step;

end Motorboat;
