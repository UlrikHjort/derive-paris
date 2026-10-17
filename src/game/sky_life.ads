--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Life in the night sky: aeroplanes crossing high over Paris with their
--  strobes and beacons, and fireworks.  There is a big show at the Eiffel
--  Tower on the 14th of July and at the Arc de Triomphe at New Year, and
--  now and then a small one somewhere in the city.

with Math3D;

package Sky_Life is

   procedure Create;
   --  Program and buffer (GL context current)

   procedure Update (Dt, Hour, Night : Float; Listener : Math3D.Vec3);
   --  Move everything; start shows when it is time

   procedure Draw (VP : Math3D.Mat4; Pixels_Per_Metre, Night : Float);
   --  Additive points, after the solid world

   procedure Start_Show (Centre : Math3D.Vec3; Big : Boolean);
   --  Fireworks at that place now (also for testing)

   function Show_Running return Boolean;

   procedure Magic_Dust (Where : Math3D.Vec3; Dt : Float);
   --  Golden glitter left behind (Father Christmas's sleigh)

end Sky_Life;
