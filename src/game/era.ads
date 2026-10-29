--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Paris in 1973 (U, or era = 1973 in ~/.deriverc): no Pyramid at the
--  Louvre, no Centre Pompidou yet (the Plateau Beaubourg is a car park),
--  no Opéra Bastille, and at Les Halles, where the old pavilions have just
--  been pulled down, the great hole behind its hoardings.  The cars are of
--  the time, and the picture has the warmth of Kodachrome.

with GL;
with Math3D;

package Era is

   function In_1973 return Boolean;
   procedure Set (On : Boolean);

   procedure Set_Uniforms (Erase, Erase_B, Erase_N, Grade : GL.GLint);
   --  The places to leave out of the city's tiles (uErase, uEraseB,
   --  uEraseN) and the colour grading (uEra), for the world program

   procedure Set_Shadow_Uniforms (Erase, Erase_B, Erase_N : GL.GLint);

   procedure Set_Cut (On : Boolean; CX, CZ, Angle, HU, HV, Y : Float := 0.0);
   --  One more box to leave out of the city's tiles, whatever the year:
   --  a window cut in a facade, to look out through (middle, turn in
   --  degrees, half sizes, from this height up)

   procedure Draw (Model, Paint : GL.GLint; Cam : Math3D.Vec3);
   --  The works at Les Halles (in 1973)

end Era;
