--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Hall B: a hall to walk round, with canvases drawn from seeds, shapes on
--  plinths and people looking at them; it is set up anew each time you
--  come in.  Its words are in data/gallery.dat.

with Ada.Strings.Unbounded;

with GL;
with Math3D;

package Hall_B is

   function Touching_Entrance (X, Z : Float) return Boolean;

   procedure Mark_Point (X, Z : out Float);
   --  A step out from the way in
   --  On foot, at the way in

   procedure New_Exhibition;
   --  Set up the hall anew (call when coming in)

   function Title return String;
   function Artist return String;
   function Heading return String;     --  for the help
   function Exit_Name return String;   --  where you come out

   procedure Entrance (X, Z, Yaw : out Float);
   procedure Way_Out (X, Z, Yaw : out Float);

   function Floor_Y return Float;

   procedure Keep_Inside (X, Z : in out Float);
   --  The walls, the partitions and the plinths

   function At_Exit (X, Z : Float) return Boolean;

   function Caption (X, Z, Yaw : Float) return String;
   --  The label of the work you are standing before and looking at
   --  (Pango markup), "" if none

   function At_Shop (X, Z, Yaw : Float) return Boolean;
   --  Standing at the shop's counter, looking at the postcards

   procedure Next_Card (Name, Text : out Ada.Strings.Unbounded.Unbounded_String;
                        Eye, Look : out Math3D.Vec3);
   --  A postcard of the next painting not yet bought (in turn): its title
   --  and words, and where to stand to take its picture

   Snapping : Boolean := False;
   --  A postcard's picture is being taken: the visitors step aside

   procedure Update (Dt : Float);

   procedure Draw (Model, Paint, Skin, Legs, Gallery : GL.GLint);
   --  With the world program in use (GL context current)

end Hall_B;
