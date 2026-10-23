--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Stunts in the plane: through the great vault of the Arc de Triomphe,
--  as Charles Godefroy flew on the 7th of August 1919, through its narrow
--  side arches, and under the bridges of the Seine.  Which bridges you
--  have flown under, and your best run of them in one flight, are kept in
--  ~/.derive_stunts.

with Math3D;

package Stunts is

   procedure Update (From, To : Math3D.Vec3; Flying : Boolean);
   --  The plane moved From -> To this frame (Flying: in the air, not
   --  crashed; a landing or a crash ends the run)

   function News return String;
   --  "" or what was just done (once), for the screen

end Stunts;
