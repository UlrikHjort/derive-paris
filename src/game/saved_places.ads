--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Places the player saved, kept in ~/.derive_places as lines of
--  "latitude longitude name" (the names can be edited there).

package Saved_Places is

   Max : constant := 50;

   procedure Load;

   function Count return Natural;
   function Name (I : Positive) return String;
   function Lat (I : Positive) return Long_Float;
   function Lon (I : Positive) return Long_Float;

   procedure Add (Name : String; Lat, Lon : Long_Float);
   --  Appends and saves the file; when full the oldest place goes

   procedure Remove (I : Positive);

end Saved_Places;
