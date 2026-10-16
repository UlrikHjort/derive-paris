--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Streaming of world tiles around the player, drawing, and collision.

with Math3D;

package World is

   procedure Init (Dir : String);
   --  Tile directory.  Call with the GL context current.

   procedure Update (Center_X, Center_Z : Float; Max_Loads : Positive := 2);
   --  Load tiles near the centre (at most Max_Loads per call) and free
   --  far ones.  Needs the GL context current.

   procedure Load_All_Near (Center_X, Center_Z : Float);
   --  Like Update but without a per-call limit (used at start-up)

   procedure Cull_To (VP : Math3D.Mat4);
   --  Following draws skip tiles outside this view-projection's frustum

   procedure Draw_Ground;
   --  Ground layers, after the solids, with depth test LESS and a cleared
   --  stencil buffer

   procedure Draw_Solid;

   procedure Collide
     (X, Z      : in out Float;
      Radius    : Float;
      Hit       : out Boolean;
      Normal_X  : out Float;
      Normal_Z  : out Float);
   --  Push a circle out of building/tree edges.  Normal is the average
   --  push direction when Hit is True.

   function Loaded_Tiles return Natural;

   procedure Pin_Tile (IX, IZ : Integer);
   --  Keep this tile loaded wherever the player is (skyline landmarks)

   procedure Set_Radius (Tiles : Positive);
   --  How many tiles around the centre to keep loaded (3 by default)

   function On_Road (X, Z : Float) return Boolean;
   --  True on a carriageway (or where no tile is loaded)

   function Obstacle_At (X, Y, Z, Radius : Float) return Boolean;
   --  True when a sphere at (X, Y, Z) touches a building, tree, lamp...

   Max_Lights : constant := 64;
   type Light_Data is array (0 .. 4 * Max_Lights - 1) of aliased Float;
   --  x, y, z, intensity per light

   procedure Nearest_Lights
     (X, Z : Float; Data : out Light_Data; Count : out Natural);
   --  The street lamps of the loaded tiles closest to (X, Z)

end World;
