--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Halloween (25 October .. 1 November): jack-o'-lanterns at the foot of
--  street lamps, and at night a few sheet ghosts floating in the streets,
--  sometimes swooping right through your car.

with GL;
with Math3D;

package Halloween is

   procedure Create_Mesh;

   procedure Update (Dt : Float; On : Boolean; Night : Float;
                     Listener, Car_Pos : Math3D.Vec3; Listener_Heading : Float);

   procedure Draw (Model_Loc : GL.GLint);
   --  With the world program in use

   procedure Ghost_Here (Where : Math3D.Vec3);
   --  For testing: a ghost there

end Halloween;
