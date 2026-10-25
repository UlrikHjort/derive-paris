--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Derive: drift through Paris, a 3D city generated from OpenStreetMap data.

with Ada.Text_IO;

with Game;
with Version;

procedure Derive is
begin
   Ada.Text_IO.Put_Line ("Dérive " & Version.Number);
   Game.Run;
end Derive;
