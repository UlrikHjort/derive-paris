--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Pedestrians walking the sidewalks of the road network around the focus.
--  They walk on both sides of the streets, pick a way at each corner and
--  step aside when the player's car comes too close.

with GL;

with Car;

package Pedestrians is

   procedure Create_Mesh;

   procedure Update (Dt : Float; Focus_X, Focus_Z, Focus_Heading : Float;
                     Player : Car.State);

   procedure Draw (Model_Loc, Cloth_Loc, Skin_Loc, Legs_Loc : GL.GLint;
                   Near_X, Near_Z : Float; Max_Distance : Float);
   --  Draw the walkers within Max_Distance of (Near_X, Near_Z).  Pass -1
   --  for the colour locations in the shadow pass.

   function Count return Natural;

   procedure Set_Sweepers (Share : Float);
   --  How many of those who appear are street sweepers (green, a broom)

   procedure Set_Santas (On : Boolean; Share : Float := 0.035);
   --  At Christmas a few of the walkers are Father Christmas

   procedure Santa_Near (X, Z : Float; Found : out Boolean; SX, SZ : out Float);
   --  A Santa within a few metres of (X, Z) who has not said hello yet

   type Keep_Out_Test is access function (X, Z : Float) return Boolean;
   procedure Set_Keep_Out (Test : Keep_Out_Test);
   --  Places walkers must not step on (a race course): they turn round

   procedure Set_Density (Factor : Float);
   --  1.0 = normal (160 people), 0 = none, up to 2.5

end Pedestrians;
