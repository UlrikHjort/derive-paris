--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The things that make a city lived in.  Along the streets: litter bins,
--  benches, rows of bollards, Morris columns with their posters, newspaper
--  kiosks, Wallace fountains, café terraces, bicycles; always in the same
--  places.  On the walls: tags and posters, somewhere else every time you
--  play.  And newspapers blowing along the street in the wind.
--
--  Built area by area (cells of 64 m) as you come near, and let go when
--  you are gone.

with Car;
with GL;
with Math3D;

package Street_Life is

   procedure Update (Dt : Float; Focus_X, Focus_Z : Float);
   --  The newspapers in the wind, around Focus

   procedure Draw (Model, Paint : GL.GLint; Cam : Math3D.Vec3);
   --  (Paint: the shader's uCarColor, for the pigeons)
   --  In the solid pass, with alpha to coverage on (posters and tags have
   --  holes); builds the cells it needs (GL context current)

   procedure Collide (S : in out Car.State);
   --  The car against what stands on the pavement

end Street_Life;
