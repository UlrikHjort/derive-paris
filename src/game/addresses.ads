--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Street addresses for the GPS: every named street, and the house
--  numbers from OpenStreetMap (tiles/addresses_*.txt, written by
--  osm2tiles).  The search ignores case and accents, and takes the
--  number before or after the street ("76 rue bonaparte").

package Addresses is

   procedure Load (Dir : String);

   Max_Results : constant := 8;

   type Result is record
      Label : String (1 .. 120);
      Last  : Natural := 0;      --  Label (1 .. Last)
      X, Z  : Float := 0.0;
   end record;
   type Result_Array is array (1 .. Max_Results) of Result;

   procedure Search (Query : String; Near_X, Near_Z : Float;
                     Found : out Result_Array; Count : out Natural);
   --  The best matches, nearest first among equals

end Addresses;
