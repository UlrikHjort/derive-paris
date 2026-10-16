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
   --  1.0 = normal (180 vehicles), 0 = none, up to 2.2

   procedure Reset;
   --  Remove all traffic; new cars arrive gradually, out of sight

   function Nearest (X, Z : Float) return Float;
   --  Distance to the nearest traffic car (m), Float'Last if none

end Traffic;
