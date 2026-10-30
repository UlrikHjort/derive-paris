--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The green metal chairs of the Luxembourg and the Tuileries, upright and
--  low, on the sand: gathered round the basins and left about the gardens
--  wherever people dragged them (data/chairs.txt).  A little different
--  every time you play.  On a fine day some have someone sitting in them.

with GL;
with Math3D;

package Garden_Chairs is

   procedure Draw (Model, Paint, Skin, Legs : GL.GLint; Cam : Math3D.Vec3;
                   Hour, Rain : Float);
   --  Built the first time you are near

end Garden_Chairs;
