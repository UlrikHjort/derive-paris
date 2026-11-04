--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Trains out of the big stations: TGVs out of the Gare du Nord, the Gare
--  de l'Est and the Gare de Lyon, and a double-deck suburban train out of
--  the Gare du Nord.  Each runs its line (train_*.txt, made by osm2tiles:
--  the tracks from the platforms out to the edge of the city, with their
--  height) out and back again, waiting at the platform in between.

with GL;
with Math3D;

package Trains is

   procedure Load (Dir : String);

   procedure Update (Dt : Float; Listener : Math3D.Vec3);

   procedure Draw (Model, Paint, Stripe, Roof : GL.GLint; Cam : Math3D.Vec3);
   --  Body in Paint, the stripe and the roof in the other two colours

   procedure Leave_Now;
   --  Every train at a platform sets off (testing)

   procedure Push (X, Z : in out Float; Feet : Float);
   --  Someone on foot by a passing train is pushed out of its way

end Trains;
