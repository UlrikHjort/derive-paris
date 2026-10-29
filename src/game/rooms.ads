--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Rooms to walk round in, each built well under its place in the city
--  and set up when you come in.

with GL;

package Rooms is

   type Room_Kind is (Room_A, Room_B, Room_C, Room_D, Room_E, Room_F, Room_Metro);

   procedure Enter (K : Room_Kind; From_X, From_Z, From_Yaw : Float);
   --  Set the room up; From: where you were (some rooms take you back)

   function Current return Room_Kind;

   procedure Mark (K : Room_Kind; X, Z : out Float; Found : out Boolean);
   --  Where in the street one is found (Found False: not like that)

   procedure Entrance (X, Z, Yaw : out Float);
   procedure Way_Out (X, Z, Yaw : out Float);
   function Floor_Y return Float;

   procedure Keep_Inside (X, Z : in out Float);
   procedure Keep_Inside (X, Z, Yaw : in out Float);
   --  (a room may take you elsewhere in it, facing another way)

   function Caption (X, Z, Yaw : Float) return String;
   --  The label of what you look at, "" if none

   procedure Set_Hour (Hour : Float);

   function At_Exit (X, Z : Float) return Boolean;
   --  At the way out (or, for a room you are only taken to, the time is up)

   function Light return Float;
   --  The shader's indoor light for this room

   procedure Update (Dt : Float; X, Z : Float);

   function Status return String;
   --  A line for the bottom of the screen (Pango markup), "" if none

   function Heading return String;   --  for the help
   function Arrival return String;   --  said when you come in
   function Leaving return String;   --  said when you go

   procedure Draw (Model, Paint, Skin, Legs, Gallery : GL.GLint);

   function Key (K : Natural) return Boolean;
   --  A key for the room (the metro's choice of station); True if used

end Rooms;
