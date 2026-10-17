--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The lie of the land: ground heights from IGN's RGE ALTI (bare earth,
--  without buildings), downloaded by scripts/download_terrain.sh into
--  data/elevation/paris.bil (32-bit floats, rows from north to south)
--  with its box in data/elevation/paris.txt.
--
--  Heights are given relative to the banks of the Seine in the centre
--  (34 m above sea level), so the old flat city keeps its level there.
--  The river bed and the lower quays are filled in from their banks: the
--  river, the quays and the bridges are built at their own depth below
--  the street.  The surface is smoothed over about 25 m.
--
--  The converter and the game read the same file and get the same ground.

package Terrain is

   procedure Load (Directory : String := "data/elevation");
   --  Quietly flat when the file is missing

   function Loaded return Boolean;

   function Height (X, Z : Long_Float) return Long_Float;
   function Height (X, Z : Float) return Float;
   --  Ground height in metres at a local position (0 outside the data)

   procedure Slope (X, Z : Float; DX, DZ : out Float);
   procedure Bounds (X0, Z0, X1, Z1 : out Float);
   --  The area with heights, in local metres (nothing when not loaded)
   --  Rise per metre east (DX) and south (DZ)

end Terrain;
