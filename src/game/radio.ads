--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The car radio (Z): after its little tune, the news on the hour and
--  whenever you switch it on, in French with the English beside it.  The
--  time, the weather and how warm it is, the mist or the heat, the Seine
--  at Austerlitz (and the flood), the traffic and the streets closed,
--  when the sun rises or sets.

package Radio is

   type Facts is record
      Hour      : Float := 12.0;
      Rain      : Float := 0.0;      --  0 .. 1
      Snow      : Float := 0.0;
      Storm     : Boolean := False;
      Closed    : Natural := 0;      --  streets closed for works and the like
      Traffic   : Float := 1.0;      --  how busy, 1 as usual
   end record;

   procedure Toggle (F : Facts);
   function On return Boolean;

   procedure Update (Dt : Float; F : Facts);

   function Text return String;
   --  The bulletin while it is read out (Pango markup), else ""

end Radio;
