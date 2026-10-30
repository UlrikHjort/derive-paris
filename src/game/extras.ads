--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Small things that make the city lively: toy sailing boats on the Grand
--  Bassin of the Jardin du Luxembourg, pushed off by children with their
--  sticks; and now and then a parachutist jumping from the top of the
--  Eiffel Tower and drifting down onto the Champ-de-Mars.

with GL;
with Math3D;

package Extras is

   procedure Update (Dt, Hour, Night : Float; Near : Math3D.Vec3);

   procedure Set_Canopy (On : Boolean; Feet : Math3D.Vec3; Yaw, Open : Float);
   --  One more canopy, over someone's head (Open: 0 .. 1)

   procedure Draw (Model, Paint, Skin, Legs : GL.GLint; Cam : Math3D.Vec3);

end Extras;
