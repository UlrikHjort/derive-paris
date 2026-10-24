--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The altimeter, while flying: a tape with your height above what is
--  below you (the ground, or the water of the Seine), the number, and how
--  fast you climb or sink.  Over the river it marks the band to fly in to
--  pass under the bridges.

with Gtk.Widget;

package Altimeter is

   function Create return Gtk.Widget.Gtk_Widget;

   procedure Set (Visible : Boolean; Height, Climb : Float; Over_Water : Boolean);
   --  Height in metres above the ground or the water; Climb in m/s

end Altimeter;
