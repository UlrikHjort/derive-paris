--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The words of two halls (data/collection.dat, scrambled): the panels,
--  the painters, the works and their years, and the halls' own words.

package Collection is

   function Panel (I : Positive) return String;     --  the eight panels
   function Painter (P : Natural) return String;    --  0 .. 9

   function Works return Natural;
   function Work_Painter (I : Positive) return Natural;
   function Work_Title (I : Positive) return String;
   function Work_Year (I : Positive) return String;

   function Word (Section : String; I : Positive) return String;
   --  The I-th line of a section ([orangerie], [orsay])

end Collection;
