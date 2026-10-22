--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  On a rare night a flying saucer streaks in, hovers over a landmark
--  near you with its lights turning and a beam of light down, and shoots
--  off into the sky again.  While it is near, the street lamps flicker
--  and the compass goes mad.

with GL;
with Math3D;

package Ufo is

   procedure Create_Mesh;

   procedure Update (Dt, Hour, Night : Float; Listener : Math3D.Vec3);

   procedure Visit (Listener : Math3D.Vec3);
   --  It comes now (also for testing)

   procedure Draw (Model_Loc, Paint_Loc : GL.GLint);
   --  The saucer, with the world program

   procedure Draw_Beam (VP : Math3D.Mat4; Cam : Math3D.Vec3);
   --  Its beam of light (additive, after the solid world)

   function In_Beam (X, Z : Float) return Boolean;
   --  Standing in its beam of light (while it shines)

   function Nearness return Float;
   --  0 .. 1: how close it is to you (lamps flicker, compass spins, sound)

   function Pan return Float;
   procedure Set_Listener_Heading (Heading : Float);

end Ufo;
