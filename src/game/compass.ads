--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  On-screen compass rose and position read-out (lat/lon, heading,
--  altitude in flight), drawn with Cairo in a corner of the window.

with Gtk.Widget;

package Compass is

   function Create return Gtk.Widget.Gtk_Widget;
   --  The widget to put in the overlay (top right)

   procedure Update (Heading_Rad : Float; Lat, Lon : Long_Float; Altitude : Float);
   --  Altitude < 0: not shown.  Redraws only when something changed.

   procedure Save_Png (File_Name : String);
   --  Draw the rose into a PNG file (for testing)

end Compass;
