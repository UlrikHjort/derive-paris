--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Postcards of the famous places (data/postcards.txt).  Come near one
--  with it before you, by car, on foot or flying low, and the game takes
--  its picture for your album, with a little of its story.  The album
--  (F4) and the pictures are kept in ~/.derive_postcards.

with Gtk.Widget;
with Math3D;

package Postcards is

   procedure Load;
   --  The places, and the cards already collected

   procedure Update (Cam, Look : Math3D.Vec3; Allowed : Boolean);
   --  Is a place before the camera?  (Allowed: not indoors, not racing...)

   function Want_Picture return Boolean;
   procedure Take_Picture (Width, Height : Natural);
   --  After a frame is drawn, into the bound framebuffer

   procedure Buy (Name, Text : String);
   --  A card bought (in a museum shop): into the album, its picture taken
   --  from the next frame drawn (the caller puts the camera before it)

   function News return String;
   --  "" or what was just collected (once)

   function Album return Gtk.Widget.Gtk_Widget;
   --  The album, to put over the game (hidden)

   function Album_Open return Boolean;
   procedure Toggle_Album;
   function Album_Key (Key : Natural) return Boolean;
   --  Left/Right to turn the pages, Escape to close; True if used

   function Collected return Natural;
   function Total return Natural;

end Postcards;
