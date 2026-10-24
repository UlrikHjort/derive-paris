--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The metro: down the stairs of an entrance to a platform of white
--  tiles, choose where to go (data/metro_stations.txt), a ride in the car
--  with the tunnel lights rushing by, and up the stairs of an entrance by
--  that station.  Seen from the game as one of the Rooms.

with GL;

package Metro is

   procedure Enter (From_X, From_Z : Float);
   --  Down from the entrance nearest (From_X, From_Z)

   procedure Entrance (X, Z, Yaw : out Float);
   procedure Way_Out (X, Z, Yaw : out Float);
   function Floor_Y return Float;
   procedure Keep_Inside (X, Z : in out Float);
   function At_Exit (X, Z : Float) return Boolean;   --  arrived
   procedure Update (Dt : Float; X, Z : Float);
   function Status return String;
   function Heading return String;
   function Arrival return String;
   function Leaving return String;
   procedure Draw (Model, Paint, Skin, Gallery : GL.GLint);

   function Key (K : Natural) return Boolean;
   --  Up/Down to choose, Enter to go; True if it was used

end Metro;
