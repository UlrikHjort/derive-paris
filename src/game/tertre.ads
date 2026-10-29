--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Montmartre: the painters at their easels on the Place du Tertre by
--  day, people watching them, and the vines of the Clos Montmartre on
--  their slope (bare in winter, gold in autumn, like the trees).

with GL;
with Math3D;

package Tertre is

   procedure Draw (Model, Paint, Skin, Legs : GL.GLint; Cam : Math3D.Vec3;
                   Hour, Rain, Time : Float);

end Tertre;
