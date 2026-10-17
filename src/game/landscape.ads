--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The lie of the land far away: a coarse sheet of the whole city's
--  ground, a little below the streets, so the hills (Montmartre, Belleville)
--  are there beyond the tiles that are loaded.  Near you the tiles' own
--  ground covers it.

package Landscape is

   procedure Create;
   --  Build the sheet (GL context current, Terrain loaded)

   procedure Draw;
   --  With the world program in use and the model matrix set to identity

end Landscape;
