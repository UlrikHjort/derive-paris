--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Up the Eiffel Tower: walk under it (on foot) and the lift takes you to
--  the top, a walkway round the spire 280 m above Paris, with a railing.
--  osm2tiles writes where the tower is to tiles/eiffel.txt.

with GL;

package Tower is

   procedure Load (File_Name : String);
   procedure Create;
   --  The railing (GL context current, after Load)

   function Known return Boolean;

   function Under (X, Z : Float) return Boolean;
   --  Standing under the tower, between its legs

   function Top_Floor_Y return Float;

   procedure Arrival (X, Z, Yaw : out Float);
   --  Where the lift lets you out at the top, looking out over Paris

   procedure Ground (X, Z, Yaw : out Float);
   --  Where you are let out at the bottom

   procedure Keep_On_Deck (X, Z : in out Float);

   procedure Draw (Model : GL.GLint);

end Tower;
