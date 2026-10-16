--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  On-disk tile format shared by the converter and the game.
--
--  A tile holds one interleaved vertex buffer, one index list per draw
--  group, the 2D collision edges of the buildings whose centroid lies in
--  the tile and the positions of its street lamps.  Ground groups are
--  drawn in painter's order (Base first), so they never z-fight; Hole
--  (the river surface at street level) is drawn at the far plane so the
--  sunken water and quay walls show through it; Solid is drawn with
--  normal depth testing.

with Interfaces;

package Tile_IO is

   Floats_Per_Vertex : constant := 10;
   --  position (3), normal (3), uv (2), material (1), seed (1)

   type Group_Id is (Base, Area, Curb, Road, Path, Hole, Deck, Mark, Solid);
   subtype Ground_Group is Group_Id range Base .. Mark;

   type Float_Array is array (Natural range <>) of Float;
   type Float_Array_Access is access Float_Array;

   Floats_Per_Edge : constant := 6;
   Floats_Per_Road : constant := 5;

   type Index_Array is array (Natural range <>) of Interfaces.Unsigned_32;
   type Index_Array_Access is access Index_Array;

   type Group_Indices is array (Group_Id) of Index_Array_Access;

   type Tile_Data is record
      IX, IZ   : Integer := 0;
      Vertices : Float_Array_Access;
      Indices  : Group_Indices;
      Edges    : Float_Array_Access;
      --  collision edges: x1, z1, x2, z2, bottom, top (6 floats each)
      Lights   : Float_Array_Access;   --  x, y, z per street lamp
      Roads    : Float_Array_Access;
      --  carriageway centre segments: x1, z1, x2, z2, half width
   end record;

   function File_Name (Dir : String; IX, IZ : Integer) return String;

   procedure Write (Dir : String; T : Tile_Data);

   procedure Read
     (Dir : String; IX, IZ : Integer; T : out Tile_Data; Found : out Boolean);

   procedure Free (T : in out Tile_Data);

   Found_Old_Format : Boolean := False;
   --  Set by Read when a tile file exists but was written by an older
   --  version of osm2tiles (the tiles need to be generated again)

end Tile_IO;
