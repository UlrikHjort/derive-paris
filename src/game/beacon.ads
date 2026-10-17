--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The Eiffel Tower at night: the beacon on top sweeps four beams over
--  Paris, and for five minutes every hour the tower sparkles.  Like the
--  real one, the lights go out at 23:45.

with Math3D;

package Beacon is

   procedure Create;
   --  Program and buffer (GL context current)

   function Lights_On (Hour, Night : Float) return Boolean;
   --  The tower is lit: after dark, until 23:45

   function Sparkle (Hour, Night : Float) return Float;
   --  0 .. 1: the first five minutes of every hour while lit

   procedure Draw (VP : Math3D.Mat4; Cam : Math3D.Vec3;
                   Time, Hour, Night, Rain : Float);
   --  The beams (additive, after the solid world)

end Beacon;
