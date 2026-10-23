--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Streets closed for a while: roadworks here and there, now and then an
--  accident with the police, a demonstration on a boulevard on Saturday
--  afternoons.  They close the street in Road_Network, so the traffic and
--  the GPS go round, and stand in the way of the car.

with GL;
with Math3D;

with Car;

package Closures is

   procedure Update (Dt : Float; Hour : Float; Saturday : Boolean; Focus_X, Focus_Z, Heading : Float);
   --  Begin new ones out of sight, end those far behind

   procedure Draw (Model, Paint, Skin, Legs, Extra : GL.GLint; Cam : Math3D.Vec3; Time : Float);
   --  In the solid pass (builds what it needs)

   procedure Collide (S : in out Car.State);

   procedure Clear;
   --  All open again (a jump across town, a race)

end Closures;
