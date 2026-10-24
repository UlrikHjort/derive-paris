--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Traffic: cars that drive along the OSM road network around the player.
--
--  The network is Road_Network.  Cars keep to the right, follow one-way
--  rules, stop at red lights, pick a random way at each junction, slow
--  down for turns and keep their distance to the car in front (including
--  the player).  They are spawned and retired in a ring around the focus
--  (the car, or the plane in flight) so the city always looks busy.

with GL;

with Car;
with Math3D;

package Traffic is

   procedure Create_Meshes;
   --  Scooter and motorbike meshes (GL context current)

   procedure Update (Dt, Time : Float; Focus_X, Focus_Z, Focus_Heading : Float;
                     Player : Car.State);
   --  Time drives the traffic lights (the shader's uTime)

   procedure Collide_Player (Player : in out Car.State);
   --  Push the player's car out of traffic cars

   procedure Draw (Model_Loc, Color_Loc : GL.GLint);
   --  Draw all cars with the car mesh; the world program must be in use.
   --  Pass Color_Loc = -1 for the shadow pass.

   function Count return Natural;

   procedure Set_Density (Factor : Float);

   procedure Set_Snow (Cover : Float);
   --  Snow lying on the streets (0 .. 1): snowploughs on the big roads
   --  1.0 = normal (180 vehicles), 0 = none, up to 2.2

   procedure Reset;
   --  Remove all traffic; new cars arrive gradually, out of sight

   procedure Clear_Corridor (A, B : Math3D.Vec3; Half_Width : Float);
   --  No cars along A .. B (a parade, a bike race): those there vanish

   procedure Set_Walker (On : Boolean; X, Z : Float);
   --  You on foot: the cars stop for you

   function Nearest (X, Z : Float) return Float;

   --  The vehicles you can hear: the nearest few, for the sound
   type Sound_Source is record
      Id       : Natural := 0;        --  0: none; stays the same per vehicle
      X, Z     : Float := 0.0;
      Speed    : Float := 0.0;        --  m/s
      Heading  : Float := 0.0;
      Kind     : Natural := 0;        --  0 car, 1 scooter, 2 motorbike
   end record;
   type Source_List is array (1 .. 8) of Sound_Source;

   function Nearby (X, Z : Float) return Source_List;
   --  Distance to the nearest traffic car (m), Float'Last if none

end Traffic;
