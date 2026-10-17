--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The date in the game and what follows from it: where the sun and the
--  moon are over Paris, the phase of the moon, and the days that are
--  celebrated (Christmas, the 14th of July, New Year).

with Math3D;

package Almanac is

   procedure Set_Date (Year, Month, Day : Integer);
   procedure Set_Today;
   --  The real date (the default)

   procedure Next_Day;
   --  The clock went past midnight

   function Year return Integer;
   function Month return Integer;
   function Day return Integer;
   function Image return String;   --  "17 October"

   function Sun (Hour : Float) return Math3D.Vec3;
   --  Direction to the sun at that local time (x east, y up, z south)

   function Moon (Hour : Float) return Math3D.Vec3;
   --  Direction to the moon

   function Moon_Age return Float;
   --  0 .. 1 through the lunar month: 0 new, 0.25 first quarter,
   --  0.5 full, 0.75 last quarter

   function Sunday return Boolean;
   function Saturday return Boolean;
   function Easter_Sunday return Boolean;
   function Christmas_Eve return Boolean; --  24 December
   function Halloween return Boolean;     --  25 October .. 1 November
   function Christmas return Boolean;    --  1 December .. 6 January
   function Bastille_Day return Boolean;  --  14 July
   function New_Years_Eve return Boolean; --  31 December

end Almanac;
