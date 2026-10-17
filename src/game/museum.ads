--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Inside the Louvre: touch the Pyramid on foot and you stand in a long
--  gallery with the Mona Lisa behind her glass (and her crowd), the Venus
--  de Milo, the Winged Victory of Samothrace on her ship, and Liberty
--  Leading the People, the Raft of the Medusa and the Coronation of
--  Napoleon on the walls.  All painted by the game itself (public domain
--  works, our own simple renderings).

with GL;
with Math3D;

package Museum is

   procedure Create;
   --  Build the gallery (GL context current, Terrain loaded)

   function Pyramid return Math3D.Vec3;
   --  The middle of the Pyramid at the ground

   function Touching_Pyramid (X, Z : Float) return Boolean;
   --  Standing against it (on foot)

   procedure Entrance (X, Z, Yaw : out Float);
   --  Where you stand when you come in, facing the gallery

   procedure Way_Out (X, Z, Yaw : out Float);
   --  Where you stand outside when you leave, facing the Pyramid

   function Floor_Y return Float;

   procedure Keep_Inside (X, Z : in out Float);
   --  The walls, the pedestals and the rail in front of the Mona Lisa

   function At_Exit (X, Z : Float) return Boolean;
   --  By the SORTIE door

   procedure Update (Dt : Float);

   procedure Draw (Model, Paint, Skin, Legs, Gallery : GL.GLint);
   --  With the world program in use; Gallery is the shader's indoor light

end Museum;
