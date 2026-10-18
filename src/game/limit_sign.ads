--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The speed limit of the street you are on, as a French road sign: a red
--  ring, the number in black.  It flashes when you drive too fast.

with Gtk.Widget;

package Limit_Sign is

   function Create return Gtk.Widget.Gtk_Widget;

   procedure Set (Limit : Natural; Over : Boolean; Time : Float);
   --  Limit 0: nothing shown

   procedure Save_Png (File_Name : String);
   --  For testing

end Limit_Sign;
