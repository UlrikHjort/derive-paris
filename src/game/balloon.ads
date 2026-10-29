--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The tethered balloon over the Parc André-Citroën: it goes up on its
--  cable to 150 m, hangs there for the view, and comes down again.  On
--  foot at its mark on the lawn, when it is down, step into the gondola
--  and go up with it; you step out when it lands.

with GL;
with Math3D;

package Balloon is

   procedure Update (Dt : Float);
   procedure Draw (Model, Paint : GL.GLint; Cam : Math3D.Vec3);

   procedure Mark (X, Z : out Float);           --  where to stand to board
   function At_Mark (X, Z : Float) return Boolean;   --  there, and it is down
   procedure Board;
   function Riding return Boolean;
   procedure Ride_Eye (X, Z, Floor_Y : out Float);
   function Landed return Boolean;               --  the ride is over
   procedure Alight (X, Z : out Float);

end Balloon;
