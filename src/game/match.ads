--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Some weekend evenings there is a match at the stadium in the west of
--  the city: people walking to it and away from it, the streets round it
--  closed, its lights over the roofs, the noise of the crowd.

with GL;
with Math3D;

package Match is

   procedure Update (Dt, Hour : Float; Cam : Math3D.Vec3);

   procedure Draw (Model, Paint, Skin, Legs : GL.GLint; Cam : Math3D.Vec3; Time : Float);

   function Crowd (Listener : Math3D.Vec3) return Float;
   --  0 .. 1

   function Radio_Line (French : Boolean) return String;
   --  For the news: tonight's match, or how it went ("" none)

   function News return String;
   --  Once, when the streets close for it ("" else)

end Match;
