--  Polygon triangulation with holes by ear clipping.
--  A port of the core of Mapbox's earcut algorithm (ISC licence),
--  without the z-order hashing (our polygons are small).

with Ada.Containers.Vectors;

package Earcut is

   type Point is record
      X, Y : Long_Float;
   end record;

   type Point_Array is array (Natural range <>) of Point;
   type Natural_Array is array (Positive range <>) of Natural;

   package Index_Vectors is new Ada.Containers.Vectors (Natural, Natural);

   procedure Triangulate
     (Coords      : Point_Array;
      Hole_Starts : Natural_Array;
      Triangles   : out Index_Vectors.Vector);
   --  Coords holds the outer ring followed by the hole rings (rings are
   --  open: the first point is not repeated).  Hole_Starts gives the index
   --  in Coords where each hole begins.  Triangles receives index triples
   --  into Coords.

end Earcut;
