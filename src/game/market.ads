--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The Christmas market on the Place du Tertre, from the first Sunday of
--  Advent to Epiphany: wooden chalets in a ring with snow on their roofs
--  and lights along the eaves, their stalls lit from inside, a big tree
--  in the middle and people strolling between them.

with GL;

package Market is

   procedure Create;
   --  Build the chalets and the tree (GL context current, Terrain loaded)

   procedure Update (Dt : Float);

   function Nearness (X, Z : Float) return Float;
   --  0 .. 1: how close (X, Z) is to the market (for its murmur)

   procedure Draw (Model, Paint, Skin, Legs : GL.GLint);
   --  With the world program in use

end Market;
