--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Christmas in Paris (December until Epiphany): big decorated trees on
--  a few squares.  The lights in the street trees are in the shader.

package Xmas is

   procedure Create;
   --  Build the trees (GL context current)

   procedure Draw;
   --  With the world program in use and the model matrix set to identity

end Xmas;
