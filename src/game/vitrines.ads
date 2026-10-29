--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Shop windows along the Boulevard Haussmann (data/windows.txt): dressed
--  for the season when the season comes, lit, moving, with people
--  stopping to look.

with GL;
with Math3D;

package Vitrines is

   procedure Draw (Model, Paint, Skin, Legs : GL.GLint; Cam : Math3D.Vec3;
                   Hour, Time : Float);

end Vitrines;
