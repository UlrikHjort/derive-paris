--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Small decals on the ground, faded in with the distance.

with GL;

package Decals is

   type Decal_Kind is (Decal_A, Decal_B, Decal_C, Decal_D, Decal_E);

   procedure Set (K : Decal_Kind; X, Z : Float);
   --  Where one is (not set: none)

   function Standing_On (X, Z : Float; K : out Decal_Kind) return Boolean;

   procedure Position (K : Decal_Kind; X, Z : out Float);   --  (testing)

   procedure Draw (Model, Extra : GL.GLint; Eye_X, Eye_Z : Float);
   --  In the solid pass with alpha to coverage on; Extra is the shader's
   --  uExtraColor (how faint)

end Decals;
