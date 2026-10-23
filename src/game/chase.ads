--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  "Suivez cette voiture !": a car pulls away ahead of you and drives
--  through the streets, turning where it likes, keeping to the road and
--  out of the closed streets.  It does not wait for you, but does not
--  race either.  After a few minutes it stops; keep it in sight until
--  then.

with GL;
with Math3D;

with Car;

package Chase is

   type Outcome is (Going, Stopped, Lost);

   procedure Start (Player : Car.State);
   procedure Stop;
   function Active return Boolean;

   procedure Update (Dt : Float; Player : Car.State);
   function State return Outcome;

   function Where return Math3D.Vec3;    --  the car (ground level)
   function Distance return Float;       --  from you, as the crow flies
   function Lost_For return Float;       --  seconds out of reach so far

   procedure Draw (Model, Paint : GL.GLint);

end Chase;
