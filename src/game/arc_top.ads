--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Up the Arc de Triomphe: walk in under the great vault (on foot) and you
--  come out on the roof terrace, 50 m up in the middle of the Étoile, with
--  the twelve avenues running off like the points of a star.  osm2tiles
--  writes where the arch is to tiles/arc.txt.

with GL;

package Arc_Top is

   procedure Load (File_Name : String);
   procedure Create;
   --  The railing round the roof (GL context current, after Load)

   function Known return Boolean;

   function Under (X, Z : Float) return Boolean;
   --  Standing under the great vault

   function Roof_Y return Float;

   procedure Centre (X, Z : out Float);

   procedure Front (AX, AZ, BX, BZ, Out_X, Out_Z : out Float);
   --  The face towards the long avenue: its two ends on the ground, and
   --  the way it faces
   --  Under the middle of the vault

   procedure Arrival (X, Z, Yaw : out Float);
   --  On the roof, looking down the Champs-Élysées

   procedure Ground (X, Z, Yaw : out Float);
   --  Back down, beside the arch

   procedure Keep_On_Roof (X, Z : in out Float);

   procedure Draw (Model : GL.GLint);

end Arc_Top;
