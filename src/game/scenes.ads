--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Scenes that come and go: a few kinds of set piece (a ring of huts, a
--  skating surface, rows of stalls, boxes along streets, light on facades,
--  glowing objects, a crowd), placed and timed by data/scenes.dat.

with Car;
with GL;

package Scenes is

   procedure Load;
   --  Read data/scenes.dat

   procedure Set_Override (Huts : Character);
   --  'y' always, 'n' never, 'a' as the data says (the ring of huts)

   procedure Create;
   --  Build them (GL context current; terrain, roads and tiles loaded)

   procedure Update (Dt, Hour, Rate : Float);
   --  Hour: the game's; Rate: game hours per real second

   procedure Draw (Model, Paint, Skin, Legs : GL.GLint; Cam_X, Cam_Z : Float);
   --  In the solid pass with alpha to coverage on (GL context current)

   function Crowd (X, Z : Float) return Float;
   --  0 .. 1: voices near (X, Z)

   function Banner return String;
   --  Big text for the middle of the screen, or ""

   procedure Collide (S : in out Car.State);

end Scenes;
