--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Falling rain (streaks) or snow (flakes) in a box that travels with the
--  camera.

with Math3D;

package Rain is

   procedure Create;
   --  Build the program and the drop buffer (GL context current)

   procedure Draw (VP : Math3D.Mat4; Cam : Math3D.Vec3;
                   Time, Amount : Float; Snow : Boolean; Pixels_Per_Metre : Float;
                   Color : Math3D.Vec3);
   --  Amount 0 .. 1; draws nothing when it is 0.  Snow: slow, drifting
   --  flakes instead of streaks.

   procedure Draw_Leaves (VP : Math3D.Mat4; Cam : Math3D.Vec3;
                          Time, Amount, Pixels_Per_Metre, Light : Float);
   --  Autumn leaves tumbling down around you; Light 0 (night) .. 1 (day)

end Rain;
