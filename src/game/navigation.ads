--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  GPS navigation: a route through the real streets to a destination,
--  turn-by-turn instructions with street names, and a minimap.

with Gtk.Widget;

with Road_Network;

package Navigation is

   function Create_Minimap return Gtk.Widget.Gtk_Widget;
   function Create_Instructions return Gtk.Widget.Gtk_Widget;

   procedure Set_Destination (Name : String; X, Z : Float);
   procedure Follow (Name : String; Path : Road_Network.Route_Vectors.Vector);
   --  Guide along this route as it is (no planning of our own, no
   --  "arrived"): a race course
   procedure Clear;
   function Active return Boolean;

   procedure Destination (Found : out Boolean; X, Z : out Float);
   function Destination_Name return String;

   procedure Update (X, Z, Heading : Float; Dt : Float; Route_Allowed : Boolean);
   --  Follow progress, re-route when off the route, update the
   --  instruction text and redraw the minimap.  Route_Allowed is False in
   --  the apartment and the plane (no driving instructions there).

   procedure Clear_Markers;
   procedure Add_Marker (X, Z : Float);
   --  Saved places, shown as small diamonds on the minimap

   procedure Show (On : Boolean);
   --  Minimap and instructions visible or not

   procedure Save_Png (File_Name : String);
   function Current_Text return String;
   --  For testing: the minimap as a picture, the instruction as text

end Navigation;
