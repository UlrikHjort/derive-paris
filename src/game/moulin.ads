--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The Moulin Rouge on the Boulevard de Clichy: the red windmill on its
--  roof, its sails turning slowly, outlined in red lights at night.

with GL;
with Math3D;

package Moulin is

   procedure Update (Dt : Float);

   procedure Draw (Model, Paint : GL.GLint; Cam : Math3D.Vec3);
   --  Built the first time it is near and its tiles are loaded

   function Door return Math3D.Vec3;
   --  On the pavement before it

end Moulin;
