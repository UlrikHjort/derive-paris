--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The Fontaine Stravinsky by the Centre Pompidou: a pool full of playful
--  sculptures, painted ones in bright colours and black machines whose
--  wheels and arms turn, all squirting water; and big painted murals on
--  the walls round the square.  Our own simple shapes, made in the spirit
--  of the place (not copies of the real works).

with GL;
with Math3D;

package Stravinsky is

   procedure Create;
   --  The sculptures (GL context current, terrain loaded)

   procedure Update (Dt : Float);

   procedure Draw (Model, Paint : GL.GLint; Cam : Math3D.Vec3);
   --  In the solid pass; the murals are found on the walls the first time
   --  the square is near and its tiles are loaded

end Stravinsky;
