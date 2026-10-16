--  Turns OSM features into renderable tile meshes and collision data.

with Osm_Model;

package World_Builder is

   procedure Build
     (M                         : Osm_Model.Model;
      South, West, North, East  : Long_Float;
      Out_Dir                   : String);
   --  Generate all tiles covering the given lat/lon box into Out_Dir.

end World_Builder;
