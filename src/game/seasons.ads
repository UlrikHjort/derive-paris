--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The weather of the seasons: the mist lying on the Seine on autumn and
--  spring mornings, the river in flood late in winter (rising up the
--  Zouave of the Pont de l'Alma, the old measure of every Paris flood,
--  over the lower quays, the boats moored), the cherries and chestnuts in
--  flower in spring, and the roads shimmering on a hot August afternoon.
--  From the date (Almanac), or for testing PARIS_MIST=1, PARIS_HEAT=1,
--  PARIS_FLOOD=metres.

with GL;
with Math3D;

package Seasons is

   procedure Update (Dt, Hour, Rain : Float; Cam : Math3D.Vec3);

   function Mist return Float;     --  0 .. 1
   function Heat return Float;     --  0 .. 1
   function Flood return Float;    --  metres above the usual level

   procedure Set_Uniforms (Mist, Mist_Y, Heat, Blossom, Petals, Flood, Seine, Seine_N : GL.GLint);
   --  For the world program (the vertex shader lifts the Seine's water)

   procedure Draw (Model, Paint : GL.GLint; Cam : Math3D.Vec3);
   --  The Zouave on his pier, and the flood over the lower quays

end Seasons;
