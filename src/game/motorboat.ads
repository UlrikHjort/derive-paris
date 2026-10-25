--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  A little motorboat to hire at the bateaux-mouches' landing by the Pont
--  de l'Alma (the yellow mark on the quay): up and down the Seine under
--  the bridges, in the bateaux-mouches' wake.  The water carries it: it
--  turns slowly, drifts on, and keeps between the quay walls.

with Car;

package Motorboat is

   procedure Hire_Point (X, Z : out Float);
   --  The yellow mark on the quay

   function At_Hire (X, Z : Float) return Boolean;
   --  On foot on the mark

   procedure Launch (S : out Car.State);
   --  The boat in the water by the landing, ready to go

   function Near_Landing (S : Car.State) return Boolean;
   --  Close enough to the landing to tie up

   procedure Step (S : in out Car.State; C : Car.Controls; Dt : Float);

end Motorboat;
