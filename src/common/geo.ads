--  Projection from WGS84 to the game's local metric coordinate system.
--
--  The world uses a fixed origin in central Paris so that tiles produced
--  from different OSM extracts line up.  Axes: X = east, Y = up,
--  Z = south (so north is -Z, matching a right-handed OpenGL frame).

package Geo is

   Origin_Lat : constant := 48.8566;   --  Hotel de Ville
   Origin_Lon : constant := 2.3522;

   Tile_Size  : constant := 250.0;     --  metres per tile edge

   procedure To_Local (Lat, Lon : Long_Float; X, Z : out Long_Float);

   function Tile_Of (C : Long_Float) return Integer;
   --  Tile index along one axis for a local coordinate

end Geo;
