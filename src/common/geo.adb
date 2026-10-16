with Ada.Numerics.Long_Elementary_Functions;

package body Geo is

   use Ada.Numerics.Long_Elementary_Functions;

   Metres_Per_Degree : constant Long_Float :=
     6_378_137.0 * Ada.Numerics.Pi / 180.0;

   Cos_Lat0 : constant Long_Float :=
     Cos (Long_Float (Origin_Lat) * Ada.Numerics.Pi / 180.0);

   procedure To_Local (Lat, Lon : Long_Float; X, Z : out Long_Float) is
   begin
      X := (Lon - Origin_Lon) * Metres_Per_Degree * Cos_Lat0;
      Z := -(Lat - Origin_Lat) * Metres_Per_Degree;
   end To_Local;

   procedure To_Lat_Lon (X, Z : Long_Float; Lat, Lon : out Long_Float) is
   begin
      Lon := Origin_Lon + X / (Metres_Per_Degree * Cos_Lat0);
      Lat := Origin_Lat - Z / Metres_Per_Degree;
   end To_Lat_Lon;

   function Tile_Of (C : Long_Float) return Integer is
     (Integer (Long_Float'Floor (C / Tile_Size)));

end Geo;
