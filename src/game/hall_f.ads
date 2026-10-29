--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Hall F: a long nave under a vault of glass, statues down the middle,
--  a great gilded clock at the end; and through the door under it, up to
--  a room behind a clock face of glass, high in the real facade, looking
--  out over the city.  One of the Rooms; its words in data/collection.dat.

with GL;
with Math3D;

package Hall_F is

   procedure Enter (Origin : Math3D.Vec3);
   procedure Entrance (X, Z, Yaw : out Float);
   function Floor_Y return Float;
   procedure Keep_Inside (X, Z : in out Float; Yaw : in out Float);
   function At_Exit (X, Z : Float) return Boolean;
   procedure Update (Dt, Hour : Float);
   function Caption (X, Z, Yaw : Float) return String;
   procedure Draw (Model, Paint, Skin, Legs, Gallery : GL.GLint);
   procedure Leave;   --  (the window in the facade closed again)

end Hall_F;
