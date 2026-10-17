--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Paris's days and little lives: the 14th of July parade with the
--  Patrouille de France, the Tour de France finish, the Fête de la Musique,
--  Paris-Plages, pigeons, a cat on the balconies of the apartment, children
--  throwing snowballs, the bateaux-mouches, the balloon over the Parc
--  André-Citroën, the Little Prince's asteroid and the Phantom of the Opera.

with GL;
with Math3D;

package Surprises is

   procedure Create;
   --  Meshes and data (GL context current)

   type Situation is record
      Dt, Hour, Night : Float := 0.0;
      Rain, Snow      : Float := 0.0;    --  falling rain, snow lying
      Listener        : Math3D.Vec3 := (0.0, 0.0, 0.0);
      Heading         : Float := 0.0;    --  where the listener looks
      Car_Pos         : Math3D.Vec3 := (0.0, 0.0, 0.0);
      Car_Speed       : Float := 0.0;
      Driving         : Boolean := True;
      Visiting        : Boolean := False;
   end record;

   procedure Update (S : Situation);

   procedure Draw (Model, Paint_Loc, Skin, Legs : GL.GLint);
   --  The solid things, with the world program

   procedure Draw_Lights (VP : Math3D.Mat4; Cam : Math3D.Vec3);
   --  Light beams (the boats' floodlights), additive

   procedure Set_Balcony (Origin, Along, Outward : Math3D.Vec3;
                          From, To, Floor_Y : Float);
   --  Where the cat walks: the balconies of the apartment

   function Jets return Float;
   function Crowd return Float;
   function Busker return Natural;
   function Busker_Level return Float;
   function Busker_Pan return Float;

   function Report return String;
   --  Testing: what is near, and where the nearest musician and flock are

   procedure Force (Name : String);
   --  Testing: "parade", "jets", "tour", "music", "plages", "pigeons",
   --  "snowball", "balloon", "asteroid", "phantom", "boats"

end Surprises;
