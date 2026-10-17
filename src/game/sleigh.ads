--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  At Christmas, now and then, Father Christmas flies over the rooftops
--  in his sleigh, pulled by eight reindeer and Rudolph.

with GL;
with Math3D;

package Sleigh is

   procedure Create_Mesh;

   procedure Update (Dt : Float; Season : Boolean; Listener : Math3D.Vec3);
   --  Out of season nothing comes; in season he passes by at random

   procedure Draw (Model_Loc, Red_Loc, Skin_Loc : GL.GLint);
   --  With the world program in use (Red_Loc = -1 in the shadow pass)

   procedure Start_Flight (Listener : Math3D.Vec3; Down_The_Street : Boolean := False);
   --  Send him past now (also for testing)

   procedure Start_At (Where : Math3D.Vec3; Heading : Float);
   --  For testing: there, flying that way

   function Visible return Boolean;
   function Dust_Point return Math3D.Vec3;
   --  Where his trail of magic dust comes from

   function Jingle return Float;
   --  0 .. 1: how loud his sleigh bells are where you are

   function Ho_Ho_Now return Boolean;
   --  True once, when he is closest to you

   function Pan return Float;
   --  Where he is heard, -1 left .. 1 right (set by Update's caller)

   procedure Set_Listener_Heading (Heading : Float);

end Sleigh;
