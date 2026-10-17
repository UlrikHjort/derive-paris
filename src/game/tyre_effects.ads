--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Skid marks left on the road by sliding or spinning tyres, and the
--  white smoke of a burnout.

with Car;
with Math3D;

package Tyre_Effects is

   procedure Create;
   --  Program and buffers (GL context current)

   procedure Update (S : Car.State; Wet : Float; Dt : Float);
   --  Lay marks and make smoke for the player's car, move the smoke

   procedure Draw_Marks (VP : Math3D.Mat4; Cam : Math3D.Vec3);
   --  After the ground

   procedure Draw_Smoke (VP : Math3D.Mat4; Cam : Math3D.Vec3;
                         Pixels_Per_Metre : Float; Light : Float);
   --  Last, over everything; Light 0 (night) .. 1 (day)

end Tyre_Effects;
