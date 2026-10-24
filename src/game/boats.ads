--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The boats on the Seine: bateaux-mouches with their passengers on the
--  open upper deck and their floodlights at night, and the long péniches
--  carrying sand and gravel, each keeping to its side of the river.  On
--  foot you can board a bateau-mouche at its landing by the Pont de
--  l'Alma and ride along; Q takes you ashore again.

with GL;
with Math3D;

package Boats is

   procedure Update (Dt : Float; Listener : Math3D.Vec3);
   --  (in the mist they go slowly and sound their horns)

   procedure Draw (Model, Paint, Skin, Legs : GL.GLint; Cam : Math3D.Vec3; Night : Float);
   procedure Draw_Lights (VP : Math3D.Mat4; Cam : Math3D.Vec3; Night : Float);
   --  The floodlights' beams, after dark

   --  Riding ------------------------------------------------------------

   function At_Landing (X, Z : Float) return Boolean;
   --  Standing at the landing (on foot): time to board

   procedure Landing (X, Z : out Float);   --  where it is (the blue mark)

   procedure Board;
   function Riding return Boolean;
   procedure Ride_Eye (X, Z, Deck_Y, Heading : out Float);
   --  Where you stand on the deck, and the way the boat goes
   procedure Ashore (X, Z : out Float);
   --  Off the boat: a place on the quay beside it

end Boats;
