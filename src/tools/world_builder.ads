--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Turns OSM features into renderable tile meshes and collision data.

with Osm_Model;

package World_Builder is

   procedure Build
     (M                         : Osm_Model.Model;
      South, West, North, East  : Long_Float;
      Out_Dir                   : String);
   --  Generate all tiles covering the given lat/lon box into Out_Dir
   --  (road network: roads.bin).

   procedure Build_Tiles
     (M                  : Osm_Model.Model;
      TX0, TX1, TZ0, TZ1 : Integer;
      Out_Dir            : String);
   --  Generate exactly the tiles TX0 .. TX1, TZ0 .. TZ1 (one chunk of a
   --  larger map; the OSM data must cover them plus a margin).  The road
   --  network goes to roads_<TX0>_<TZ0>.bin.

end World_Builder;
