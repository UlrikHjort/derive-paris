--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The Funiculaire de Montmartre: two cabins side by side on their slope
--  from the Place Suzanne-Valadon up to the Sacré-Cœur, one going up as
--  the other comes down, a minute and a half each way with the waits.  On
--  foot at the lower or the upper station, stand on its mark to board the
--  cabin there; you get off at the other end.

with GL;
with Math3D;

package Funicular is

   procedure Update (Dt : Float);

   procedure Draw (Model, Paint : GL.GLint; Cam : Math3D.Vec3);

   function At_Station (X, Z : Float) return Boolean;
   --  On foot on a station's mark, with the cabin there and its doors open

   procedure Lower_Mark (X, Z : out Float);
   --  Where to stand at the bottom

   procedure Board (X, Z : Float);
   function Riding return Boolean;
   procedure Ride_Eye (X, Z, Floor_Y : out Float);
   --  Where you stand in the cabin
   function Arrived return Boolean;
   procedure Alight (X, Z : out Float);
   --  Off at the end of the ride, a step out of the station

end Funicular;
