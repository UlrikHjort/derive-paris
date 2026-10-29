--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Hall E: two oval rooms under a white light, the walls one long
--  painted pond, and below them a gallery of paintings.  Its words are in
--  data/collection.dat.  One of the Rooms.

with GL;
with Math3D;

package Hall_E is

   procedure Enter (Origin : Math3D.Vec3);
   procedure Entrance (X, Z, Yaw : out Float);
   function Floor_Y return Float;
   procedure Keep_Inside (X, Z : in out Float);
   function At_Exit (X, Z : Float) return Boolean;
   procedure Update (Dt : Float);
   function Caption (X, Z, Yaw : Float) return String;
   procedure Draw (Model, Paint, Skin, Legs, Gallery : GL.GLint);

end Hall_E;
