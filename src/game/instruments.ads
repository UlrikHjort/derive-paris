--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The instrument panel (I): the gear, on an H-pattern for the manual
--  gearbox or R N D for the automatic, the rev counter, the speed and,
--  with a racing wheel, the three pedals.

with Gtk.Widget;

package Instruments is

   type Reading is record
      Gear     : Integer := 0;       --  -1 reverse, 0 neutral, 1 .. 6
      Manual   : Boolean := False;
      Grinding : Boolean := False;   --  the lever is in a gear that is not in
      Lever    : Integer := 0;       --  where the shifter is (manual)
      Rpm      : Float := 0.0;
      Kmh      : Float := 0.0;
      Pedals   : Boolean := False;   --  show the pedals (a wheel is used)
      Clutch, Brake, Throttle : Float := 0.0;
   end record;

   function Create return Gtk.Widget.Gtk_Widget;

   procedure Update (R : Reading);
   --  Redraws when something visible changed

   procedure Save_Png (File_Name : String);
   --  For testing: the panel as a picture

end Instruments;
