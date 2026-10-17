--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Thunderstorms: lightning bolts from the clouds to the city (sometimes
--  into the Eiffel Tower), the sky flashing, and thunder that arrives
--  late from far away.

with Math3D;

package Storm is

   procedure Create;

   procedure Update (Dt : Float; Active : Boolean; Listener : Math3D.Vec3);
   --  While Active, lightning strikes every few seconds

   procedure Strike (Listener : Math3D.Vec3; Distance : Float := -1.0);
   --  A strike now (Distance < 0: random)

   procedure Strike_At (Ground, Listener : Math3D.Vec3);
   --  A strike at that place (for testing)

   function Flash return Float;
   --  0 .. 1: how bright the sky is lit by lightning right now

   procedure Draw (VP : Math3D.Mat4; Cam : Math3D.Vec3);
   --  The bolts (additive), after the solid world

end Storm;
