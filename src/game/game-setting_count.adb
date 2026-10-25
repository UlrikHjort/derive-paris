--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
separate (Game)
function Setting_Count return Natural is
begin
   return Settings_Kind'Pos (Settings_Kind'Last) + 1;
end Setting_Count;
