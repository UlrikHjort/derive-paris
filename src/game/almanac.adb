--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Calendar;
with Ada.Calendar.Arithmetic;
with Ada.Calendar.Formatting;
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;

package body Almanac is

   use Ada.Numerics.Elementary_Functions;
   use Math3D;

   Pi       : constant := Ada.Numerics.Pi;
   Latitude : constant := 48.85 * Pi / 180.0;
   Tilt     : constant := 23.44 * Pi / 180.0;

   Today : Ada.Calendar.Time := Ada.Calendar.Clock;

   procedure Set_Date (Year, Month, Day : Integer) is
   begin
      Today := Ada.Calendar.Time_Of (Ada.Calendar.Year_Number (Year),
                                     Ada.Calendar.Month_Number (Month),
                                     Ada.Calendar.Day_Number (Day), 43_200.0);
   end Set_Date;

   procedure Set_Today is
   begin
      Today := Ada.Calendar.Clock;
   end Set_Today;

   procedure Next_Day is
   begin
      Today := Ada.Calendar.Arithmetic."+" (Today, Ada.Calendar.Arithmetic.Day_Count (1));
   end Next_Day;

   function Year return Integer is (Integer (Ada.Calendar.Year (Today)));
   function Month return Integer is (Integer (Ada.Calendar.Month (Today)));
   function Day return Integer is (Integer (Ada.Calendar.Day (Today)));

   Month_Names : constant array (1 .. 12) of access constant String :=
     (new String'("January"), new String'("February"), new String'("March"),
      new String'("April"), new String'("May"), new String'("June"),
      new String'("July"), new String'("August"), new String'("September"),
      new String'("October"), new String'("November"), new String'("December"));

   function Image return String is
      D : constant String := Integer'Image (Day);
   begin
      return D (D'First + 1 .. D'Last) & " " & Month_Names (Month).all;
   end Image;

   function Day_Of_Year return Integer is
      Days_Before : constant array (1 .. 12) of Integer :=
        (0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334);
   begin
      return Days_Before (Month) + Day;
   end Day_Of_Year;

   --  The sun's declination today
   function Declination return Float is
     (Tilt * Sin (2.0 * Pi * Float (284 + Day_Of_Year) / 365.0));

   --  Summer time from the last Sunday of March to the last of October
   --  (near enough: the 25th to the 25th)
   function Summer_Time return Boolean is
     ((Month > 3 and then Month < 10)
      or else (Month = 3 and then Day >= 25)
      or else (Month = 10 and then Day < 25));

   --  Local clock time of the sun's highest point in Paris (CET is an hour
   --  ahead of the sun at 2.35 degrees east, plus the summer hour)
   function Noon return Float is
     (12.0 + 1.0 - 2.35 / 15.0 + (if Summer_Time then 1.0 else 0.0));

   --  Direction to a body at hour angle H (radians, west positive) and
   --  declination Dec, seen from Paris
   function Direction (H, Dec : Float) return Vec3 is
      East  : constant Float := -Cos (Dec) * Sin (H);
      North : constant Float := Cos (Latitude) * Sin (Dec) - Sin (Latitude) * Cos (Dec) * Cos (H);
      Up    : constant Float := Sin (Latitude) * Sin (Dec) + Cos (Latitude) * Cos (Dec) * Cos (H);
   begin
      return Normalize ((East, Up, -North));
   end Direction;

   function Sun (Hour : Float) return Vec3 is
     (Direction ((Hour - Noon) * Pi / 12.0, Declination));

   --  Days since a known new moon (6 January 2000, 18:14 UTC)
   function Moon_Age return Float is
      use Ada.Calendar;
      Epoch : constant Time := Time_Of (2000, 1, 6, 18.0 * 3600.0 + 14.0 * 60.0);
      Days  : constant Float := Float (Today - Epoch) / 86_400.0;
      Month_Length : constant := 29.530589;
      A : constant Float := Days / Month_Length;
   begin
      return A - Float'Floor (A);
   end Moon_Age;

   --  The moon is behind the sun in the sky by its age: new with the sun,
   --  full opposite it (rising at sunset), first quarter in the evening
   function Moon (Hour : Float) return Vec3 is
      Behind : constant Float := 2.0 * Pi * Moon_Age;
      --  it follows the ecliptic: high in winter when full, low in summer
      Dec : constant Float :=
        Tilt * Sin (2.0 * Pi * Float (284 + Day_Of_Year) / 365.0 + Behind);
   begin
      return Direction ((Hour - Noon) * Pi / 12.0 - Behind, Dec);
   end Moon;

   function Sunday return Boolean is
     (Ada.Calendar.Formatting."=" (Ada.Calendar.Formatting.Day_Of_Week (Today),
                                  Ada.Calendar.Formatting.Sunday));
   function Saturday return Boolean is
     (Ada.Calendar.Formatting."=" (Ada.Calendar.Formatting.Day_Of_Week (Today),
                                  Ada.Calendar.Formatting.Saturday));

   --  Easter Sunday (the Gregorian computus)
   function Easter_Sunday return Boolean is
      Y : constant Integer := Year;
      A : constant Integer := Y mod 19;
      B : constant Integer := Y / 100;
      C : constant Integer := Y mod 100;
      D : constant Integer := B / 4;
      E : constant Integer := B mod 4;
      F : constant Integer := (B + 8) / 25;
      G : constant Integer := (B - F + 1) / 3;
      H : constant Integer := (19 * A + B - D - G + 15) mod 30;
      I : constant Integer := C / 4;
      K : constant Integer := C mod 4;
      L : constant Integer := (32 + 2 * E + 2 * I - H - K) mod 7;
      M : constant Integer := (A + 11 * H + 22 * L) / 451;
      N : constant Integer := H + L - 7 * M + 114;
   begin
      return Month = N / 31 and then Day = N mod 31 + 1;
   end Easter_Sunday;

   function Christmas_Eve return Boolean is (Month = 12 and then Day = 24);
   function Halloween return Boolean is
     ((Month = 10 and then Day >= 25) or else (Month = 11 and then Day = 1));

   --  0 before From, 1 after To, a ramp between (days of the year)
   function Ramp (From, To : Integer) return Float is
     (Float'Max (0.0, Float'Min (1.0, Float (Day_Of_Year - From) / Float (To - From))));

   --  Paris: the plane trees turn from late September, are at their most
   --  colourful late in October, bare by December, green again in April
   function Autumn_Colour return Float is
     (if Day_Of_Year < 150 then 0.0 else Ramp (268, 308));
   function Bare return Float is
     (if Day_Of_Year >= 150 then 0.85 * Ramp (298, 335)
      else 0.85 * (1.0 - Ramp (80, 118)));
   function Leaf_Litter return Float is
     (if Day_Of_Year >= 150 then Ramp (280, 305) * (1.0 - 0.7 * Ramp (335, 365))
      else 0.3 * (1.0 - Ramp (1, 40)));
   function Leaves_Falling return Float is
     (if Day_Of_Year < 150 then 0.0
      else 0.12 * Ramp (283, 300) * (1.0 - Ramp (325, 340)));

   function Christmas return Boolean is
     (Month = 12 or else (Month = 1 and then Day <= 6));
   --  The first Sunday of Advent: four Sundays before Christmas (27 November
   --  .. 3 December)
   function Advent return Boolean is
      use Ada.Calendar.Formatting;
      Eve   : constant Ada.Calendar.Time := Ada.Calendar.Time_Of (Year, 12, 24, 43_200.0);
      Back  : constant Integer := (Day_Name'Pos (Day_Of_Week (Eve)) + 1) mod 7;   --  to the Sunday before
      First : constant Integer := 24 - Back - 21;    --  in December; 0 and below in November
   begin
      return (Month = 1 and then Day <= 6)
        or else (Month = 12 and then Day >= First)
        or else (Month = 11 and then Day - 30 >= First);
   end Advent;

   function Bastille_Day return Boolean is (Month = 7 and then Day = 14);
   function New_Years_Eve return Boolean is (Month = 12 and then Day = 31);

end Almanac;
