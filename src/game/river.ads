--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The Seine's channel, for the plane: between the quay walls it may fly
--  down to just above the water (and so under the bridges).  From the
--  middle line in data/seine.txt.

package River is

   function In_Channel (X, Z : Float) return Boolean;
   --  Over the water, well clear of the quay walls

   Depth : constant := 5.5;
   --  How far below the street the water lies there (about)

end River;
