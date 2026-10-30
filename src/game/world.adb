--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Containers.Hashed_Maps;
with Ada.Numerics.Elementary_Functions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with System.Storage_Elements;

with GL;
with Geo;
with Terrain;
with Tile_IO;
with Notes;

package body World is

   use GL;
   use Tile_IO;
   use Ada.Numerics.Elementary_Functions;

   Load_Radius   : Natural := 3;   --  tiles kept around the centre
   Unload_Radius : Natural := 5;

   procedure Set_Radius (Tiles : Positive) is
   begin
      Load_Radius := Tiles;
      Unload_Radius := Tiles + 2;
   end Set_Radius;

   type Tile_Key is record
      IX, IZ : Integer;
   end record;

   function Hash (K : Tile_Key) return Ada.Containers.Hash_Type is
     (Ada.Containers.Hash_Type ((K.IX * 7919 + K.IZ) mod 2**30));

   type Group_Range is record
      First, Count : Natural := 0;
   end record;

   type Group_Ranges is array (Group_Id) of Group_Range;

   type Tile_Slot is record
      Present : Boolean := False;   --  False: no file for this tile
      VAO     : aliased GLuint := 0;
      VBO     : aliased GLuint := 0;
      EBO     : aliased GLuint := 0;
      Groups  : Group_Ranges;
      Edges   : Float_Array_Access;
      Lights  : Float_Array_Access;
      Roads   : Float_Array_Access;
   end record;

   package Tile_Maps is new Ada.Containers.Hashed_Maps
     (Tile_Key, Tile_Slot, Hash, "=");

   Tiles    : Tile_Maps.Map;

   package Pin_Maps is new Ada.Containers.Hashed_Maps (Tile_Key, Boolean, Hash, "=");
   Pinned   : Pin_Maps.Map;

   procedure Pin_Tile (IX, IZ : Integer) is
   begin
      Pinned.Include ((IX, IZ), True);
   end Pin_Tile;
   Tile_Dir : Ada.Strings.Unbounded.Unbounded_String;

   procedure Init (Dir : String) is
   begin
      Tile_Dir := Ada.Strings.Unbounded.To_Unbounded_String (Dir);
   end Init;

   function Offset (Bytes : Natural) return System.Address is
     (System.Storage_Elements.To_Address
        (System.Storage_Elements.Integer_Address (Bytes)));

   procedure Upload (Data : Tile_Data; Slot : in out Tile_Slot) is
      Stride : constant := Floats_Per_Vertex * 4;
      Total  : Natural := 0;
   begin
      for G in Group_Id loop
         Total := Total + Data.Indices (G)'Length;
      end loop;

      glGenVertexArrays (1, Slot.VAO'Address);
      glBindVertexArray (Slot.VAO);

      glGenBuffers (1, Slot.VBO'Address);
      glBindBuffer (GL_ARRAY_BUFFER, Slot.VBO);
      glBufferData (GL_ARRAY_BUFFER, GLsizeiptr (Data.Vertices'Length * 4),
                    Data.Vertices.all'Address, GL_STATIC_DRAW);

      --  Concatenate all groups into one index buffer
      declare
         All_Idx : Index_Array (0 .. Total - 1);
         Pos     : Natural := 0;
      begin
         for G in Group_Id loop
            Slot.Groups (G) := (First => Pos, Count => Data.Indices (G)'Length);
            for I of Data.Indices (G).all loop
               All_Idx (Pos) := I;
               Pos := Pos + 1;
            end loop;
         end loop;
         glGenBuffers (1, Slot.EBO'Address);
         glBindBuffer (GL_ELEMENT_ARRAY_BUFFER, Slot.EBO);
         glBufferData (GL_ELEMENT_ARRAY_BUFFER, GLsizeiptr (Total * 4),
                       (if Total > 0 then All_Idx'Address else System.Null_Address),
                       GL_STATIC_DRAW);
      end;

      glVertexAttribPointer (0, 3, GL_FLOAT, GL_FALSE, Stride, Offset (0));
      glEnableVertexAttribArray (0);
      glVertexAttribPointer (1, 3, GL_FLOAT, GL_FALSE, Stride, Offset (12));
      glEnableVertexAttribArray (1);
      glVertexAttribPointer (2, 2, GL_FLOAT, GL_FALSE, Stride, Offset (24));
      glEnableVertexAttribArray (2);
      glVertexAttribPointer (3, 1, GL_FLOAT, GL_FALSE, Stride, Offset (32));
      glEnableVertexAttribArray (3);
      glVertexAttribPointer (4, 1, GL_FLOAT, GL_FALSE, Stride, Offset (36));
      glEnableVertexAttribArray (4);

      glBindVertexArray (0);
   end Upload;

   procedure Load_Tile (Key : Tile_Key) is
      Data  : Tile_Data;
      Found : Boolean;
      Slot  : Tile_Slot;
   begin
      Read (Ada.Strings.Unbounded.To_String (Tile_Dir), Key.IX, Key.IZ, Data, Found);
      if Found then
         Slot.Present := True;
         Upload (Data, Slot);
         Slot.Edges := Data.Edges;
         Slot.Lights := Data.Lights;
         Slot.Roads := Data.Roads;
         Data.Edges := null;    --  keep edges, lights and roads, free the rest
         Data.Lights := null;
         Data.Roads := null;
         Free (Data);
      end if;
      Tiles.Include (Key, Slot);
   end Load_Tile;

   procedure Unload_Tile (Slot : in out Tile_Slot) is
      Dummy : Tile_Data;
   begin
      if Slot.Present then
         glDeleteBuffers (1, Slot.VBO'Address);
         glDeleteBuffers (1, Slot.EBO'Address);
         glDeleteVertexArrays (1, Slot.VAO'Address);
         Dummy.Edges := Slot.Edges;
         Dummy.Lights := Slot.Lights;
         Dummy.Roads := Slot.Roads;
         Free (Dummy);
      end if;
   end Unload_Tile;

   procedure Update_Internal (Center_X, Center_Z : Float; Max_Loads : Natural) is
      CX    : constant Integer := Geo.Tile_Of (Long_Float (Center_X));
      CZ    : constant Integer := Geo.Tile_Of (Long_Float (Center_Z));
      Loads : Natural := 0;
   begin
      --  Unload far tiles
      declare
         use Tile_Maps;
         C         : Cursor := Tiles.First;
         To_Delete : array (1 .. 64) of Tile_Key;
         N         : Natural := 0;
      begin
         while Has_Element (C) and then N < To_Delete'Last loop
            declare
               K : constant Tile_Key := Key (C);
            begin
               if (abs (K.IX - CX) > Unload_Radius or else abs (K.IZ - CZ) > Unload_Radius)
                 and then not Pinned.Contains (K)
               then
                  N := N + 1;
                  To_Delete (N) := K;
               end if;
            end;
            Next (C);
         end loop;
         for I in 1 .. N loop
            declare
               Slot : Tile_Slot := Tiles (To_Delete (I));
            begin
               Unload_Tile (Slot);
               Tiles.Delete (To_Delete (I));
            end;
         end loop;
      end;

      --  Skyline landmarks first, then near tiles, closest rings first
      for C in Pinned.Iterate loop
         if not Tiles.Contains (Pin_Maps.Key (C)) then
            if Max_Loads > 0 and then Loads >= Max_Loads then
               return;
            end if;
            Load_Tile (Pin_Maps.Key (C));
            Loads := Loads + 1;
         end if;
      end loop;

      for Ring in 0 .. Load_Radius loop
         for DX in -Ring .. Ring loop
            for DZ in -Ring .. Ring loop
               if (abs DX = Ring or else abs DZ = Ring)
                 and then not Tiles.Contains ((CX + DX, CZ + DZ))
               then
                  if Max_Loads > 0 and then Loads >= Max_Loads then
                     return;
                  end if;
                  Load_Tile ((CX + DX, CZ + DZ));
                  Loads := Loads + 1;
               end if;
            end loop;
         end loop;
      end loop;
   end Update_Internal;

   procedure Update (Center_X, Center_Z : Float; Max_Loads : Positive := 2) is
   begin
      Update_Internal (Center_X, Center_Z, Max_Loads);
   end Update;

   procedure Load_All_Near (Center_X, Center_Z : Float) is
   begin
      Update_Internal (Center_X, Center_Z, 0);
      Notes.Say ("Loaded" & Natural'Image (Natural (Tiles.Length)) & " tiles");
      if Tile_IO.Found_Old_Format then
         Ada.Text_IO.Put_Line
           ("The tiles were made by an older osm2tiles: run ""make tiles""");
      end if;
   end Load_All_Near;

   type Plane is array (0 .. 3) of Float;
   Planes : array (1 .. 6) of Plane := (others => (0.0, 0.0, 0.0, 1.0));

   procedure Cull_To (VP : Math3D.Mat4) is
      function Row (R : Natural) return Plane is
        ((VP (R), VP (4 + R), VP (8 + R), VP (12 + R)));
      R0 : constant Plane := Row (0);
      R1 : constant Plane := Row (1);
      R2 : constant Plane := Row (2);
      R3 : constant Plane := Row (3);
   begin
      for K in 0 .. 3 loop
         Planes (1) (K) := R3 (K) + R0 (K);
         Planes (2) (K) := R3 (K) - R0 (K);
         Planes (3) (K) := R3 (K) + R1 (K);
         Planes (4) (K) := R3 (K) - R1 (K);
         Planes (5) (K) := R3 (K) + R2 (K);
         Planes (6) (K) := R3 (K) - R2 (K);
      end loop;
   end Cull_To;

   --  Tile bounding box against the frustum (positive-vertex test)
   function Visible (K : Tile_Key) return Boolean is
      X0 : constant Float := Float (K.IX) * Geo.Tile_Size;
      Z0 : constant Float := Float (K.IZ) * Geo.Tile_Size;
      X1 : constant Float := X0 + Geo.Tile_Size;
      Z1 : constant Float := Z0 + Geo.Tile_Size;
      Y0 : constant Float := -8.0;
      Y1 : constant Float := 160.0;
   begin
      for P of Planes loop
         if P (0) * (if P (0) >= 0.0 then X1 else X0)
           + P (1) * (if P (1) >= 0.0 then Y1 else Y0)
           + P (2) * (if P (2) >= 0.0 then Z1 else Z0)
           + P (3) < 0.0
         then
            return False;
         end if;
      end loop;
      return True;
   end Visible;

   procedure Draw_Group (G : Group_Id) is
      use Tile_Maps;
      C : Cursor := Tiles.First;
   begin
      while Has_Element (C) loop
         declare
            Slot : Tile_Slot renames Tiles.Constant_Reference (C).Element.all;
         begin
            if Slot.Present and then Slot.Groups (G).Count > 0
              and then Visible (Key (C))
            then
               glBindVertexArray (Slot.VAO);
               glDrawElements (GL_TRIANGLES, GLsizei (Slot.Groups (G).Count),
                               GL_UNSIGNED_INT, Offset (Slot.Groups (G).First * 4));
            end if;
         end;
         Next (C);
      end loop;
   end Draw_Group;

   procedure Draw_Ground_Depth is
      Push : constant GLfloat := GLfloat (4.0);
   begin
      --  Depth only, a little further back than the ground really is (see
      --  where it is called, too), so that the coplanar layers of Draw_Ground
      --  all pass, but ground further off, hidden behind a hill, does not.  Only the river's
      --  surface claims its pixels, as in Draw_Ground.
      glColorMask (GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
      glEnable (GL_POLYGON_OFFSET_FILL);
      glPolygonOffset (Push, Push);
      glEnable (GL_STENCIL_TEST);
      glStencilFunc (GL_NOTEQUAL, 1, 16#FF#);
      glStencilOp (GL_KEEP, GL_KEEP, GL_KEEP);
      for G in reverse Ground_Group loop
         if G = Hole then
            glStencilOp (GL_KEEP, GL_KEEP, GL_REPLACE);
            glDepthMask (GL_FALSE);
            Draw_Group (G);
            glDepthMask (GL_TRUE);
            glStencilOp (GL_KEEP, GL_KEEP, GL_KEEP);
         else
            Draw_Group (G);
         end if;
      end loop;
      glDisable (GL_STENCIL_TEST);
      glClear (GL_STENCIL_BUFFER_BIT);
      glPolygonOffset (GLfloat (0.0), GLfloat (0.0));
      glDisable (GL_POLYGON_OFFSET_FILL);
      glColorMask (GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
      glBindVertexArray (0);
   end Draw_Ground_Depth;

   procedure Draw_Ground is
   begin
      --  The ground layers are coplanar.  They are drawn top layer first
      --  (and each layer's triangles were stored in reverse order), and
      --  the stencil lets only the first fragment per pixel through: the
      --  same result as painting bottom-up, but every ground pixel is
      --  shaded once, and not at all where a building already covers it.
      --  On a hill the ground also stands in front of itself: the depth
      --  from Draw_Ground_Depth keeps what is behind it from claiming a pixel.
      glDepthFunc (GL_LEQUAL);
      glEnable (GL_STENCIL_TEST);
      glStencilFunc (GL_NOTEQUAL, 1, 16#FF#);
      glStencilOp (GL_KEEP, GL_KEEP, GL_REPLACE);
      for G in reverse Ground_Group loop
         if G = Hole then
            --  The river surface at street level only claims its pixels,
            --  so the sunken water and quay walls drawn before stay visible
            glColorMask (GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
            glDepthMask (GL_FALSE);
            Draw_Group (G);
            glColorMask (GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
            glDepthMask (GL_TRUE);
         else
            Draw_Group (G);
         end if;
      end loop;
      glDisable (GL_STENCIL_TEST);
      glDepthFunc (GL_LESS);
      glBindVertexArray (0);
   end Draw_Ground;

   procedure Draw_Solid is
   begin
      Draw_Group (Solid);
      glBindVertexArray (0);
   end Draw_Solid;

   procedure For_Walls_Near (X, Z, Radius : Float) is
   begin
      for TX in Geo.Tile_Of (Long_Float (X - Radius)) .. Geo.Tile_Of (Long_Float (X + Radius)) loop
         for TZ in Geo.Tile_Of (Long_Float (Z - Radius)) .. Geo.Tile_Of (Long_Float (Z + Radius)) loop
            declare
               C : constant Tile_Maps.Cursor := Tiles.Find ((TX, TZ));
            begin
               if Tile_Maps.Has_Element (C) and then Tile_Maps.Element (C).Present then
                  declare
                     E : Float_Array renames Tile_Maps.Element (C).Edges.all;
                     I : Natural := E'First;
                  begin
                     while I + Floats_Per_Edge - 1 <= E'Last loop
                        declare
                           MX : constant Float := 0.5 * (E (I) + E (I + 2));
                           MZ : constant Float := 0.5 * (E (I + 1) + E (I + 3));
                        begin
                           --  an edge is kept in every tile it crosses: take
                           --  it from the one holding its middle
                           if Geo.Tile_Of (Long_Float (MX)) = TX and then Geo.Tile_Of (Long_Float (MZ)) = TZ
                             and then abs (MX - X) <= Radius and then abs (MZ - Z) <= Radius
                           then
                              Visit (E (I), E (I + 1), E (I + 2), E (I + 3), E (I + 4), E (I + 5));
                           end if;
                        end;
                        I := I + Floats_Per_Edge;
                     end loop;
                  end;
               end if;
            end;
         end loop;
      end loop;
   end For_Walls_Near;

   function Ray_Free (From, To : Math3D.Vec3) return Float is
      DX : constant Float := To.X - From.X;
      DZ : constant Float := To.Z - From.Z;
      Best : Float := 1.0;
   begin
      for TX in Geo.Tile_Of (Long_Float (Float'Min (From.X, To.X)))
             .. Geo.Tile_Of (Long_Float (Float'Max (From.X, To.X)))
      loop
         for TZ in Geo.Tile_Of (Long_Float (Float'Min (From.Z, To.Z)))
                .. Geo.Tile_Of (Long_Float (Float'Max (From.Z, To.Z)))
         loop
            declare
               C : constant Tile_Maps.Cursor := Tiles.Find ((TX, TZ));
            begin
               if Tile_Maps.Has_Element (C) and then Tile_Maps.Element (C).Present then
                  declare
                     E : Float_Array renames Tile_Maps.Element (C).Edges.all;
                     I : Natural := E'First;
                  begin
                     while I + Floats_Per_Edge - 1 <= E'Last loop
                        declare
                           AX : constant Float := E (I);
                           AZ : constant Float := E (I + 1);
                           EX : constant Float := E (I + 2) - AX;
                           EZ : constant Float := E (I + 3) - AZ;
                           Den : constant Float := DX * EZ - DZ * EX;
                        begin
                           --  a wall (not a trunk or a post) crossing the line
                           if abs Den > 1.0E-6 and then EX * EX + EZ * EZ > 1.5 ** 2 then
                              declare
                                 T : constant Float := ((AX - From.X) * EZ - (AZ - From.Z) * EX) / Den;
                                 U : constant Float := ((AX - From.X) * DZ - (AZ - From.Z) * DX) / Den;
                              begin
                                 if T >= 0.0 and then T < Best and then U >= 0.0 and then U <= 1.0 then
                                    declare
                                       Y : constant Float := From.Y + T * (To.Y - From.Y);
                                    begin
                                       if Y >= E (I + 4) and then Y <= E (I + 5) then
                                          Best := T;
                                       end if;
                                    end;
                                 end if;
                              end;
                           end if;
                        end;
                        I := I + Floats_Per_Edge;
                     end loop;
                  end;
               end if;
            end;
         end loop;
      end loop;
      return Best;
   end Ray_Free;

   procedure Collide
     (X, Z      : in out Float;
      Radius    : Float;
      Hit       : out Boolean;
      Normal_X  : out Float;
      Normal_Z  : out Float)
   is
      Sum_X, Sum_Z : Float := 0.0;
      Ground_Here  : constant Float := Terrain.Height (X, Z);
   begin
      Hit := False;
      for Iteration in 1 .. 4 loop
         declare
            Pushed : Boolean := False;
         begin
            --  Edges are stored in every tile they cross: only the tiles
            --  under the circle matter
            for TX in Geo.Tile_Of (Long_Float (X - Radius)) .. Geo.Tile_Of (Long_Float (X + Radius)) loop
               for TZ in Geo.Tile_Of (Long_Float (Z - Radius)) .. Geo.Tile_Of (Long_Float (Z + Radius)) loop
                  declare
                     C : constant Tile_Maps.Cursor := Tiles.Find ((TX, TZ));
                  begin
                     if Tile_Maps.Has_Element (C) and then Tile_Maps.Element (C).Present then
                        declare
                           E : Float_Array renames Tile_Maps.Element (C).Edges.all;
                           I : Natural := E'First;
                        begin
                           while I + Floats_Per_Edge - 1 <= E'Last loop
                              declare
                                 AX : constant Float := E (I);
                                 AZ : constant Float := E (I + 1);
                                 BX : constant Float := E (I + 2);
                                 BZ : constant Float := E (I + 3);
                              begin
                                 --  only what stands on the ground stops a car
                                 --  (edges carry absolute heights: hills)
                                 if E (I + 4) < Ground_Here + 2.0 and then E (I + 5) > Ground_Here + 0.2
                                   and then X + Radius >= Float'Min (AX, BX)
                                   and then X - Radius <= Float'Max (AX, BX)
                                   and then Z + Radius >= Float'Min (AZ, BZ)
                                   and then Z - Radius <= Float'Max (AZ, BZ)
                                 then
                                    declare
                                       EX : constant Float := BX - AX;
                                       EZ : constant Float := BZ - AZ;
                                       L2 : constant Float := EX * EX + EZ * EZ;
                                       T  : Float := 0.0;
                                       PX, PZ, D : Float;
                                    begin
                                       if L2 > 1.0E-8 then
                                          T := Float'Max (0.0, Float'Min
                                            (1.0, ((X - AX) * EX + (Z - AZ) * EZ) / L2));
                                       end if;
                                       PX := X - (AX + T * EX);
                                       PZ := Z - (AZ + T * EZ);
                                       D := Sqrt (PX * PX + PZ * PZ);
                                       if D < Radius and then D > 1.0E-6 then
                                          X := X + PX / D * (Radius - D);
                                          Z := Z + PZ / D * (Radius - D);
                                          Sum_X := Sum_X + PX / D;
                                          Sum_Z := Sum_Z + PZ / D;
                                          Hit := True;
                                          Pushed := True;
                                       end if;
                                    end;
                                 end if;
                              end;
                              I := I + Floats_Per_Edge;
                           end loop;
                        end;
                     end if;
                  end;
               end loop;
            end loop;
            exit when not Pushed;
         end;
      end loop;

      declare
         L : constant Float := Sqrt (Sum_X * Sum_X + Sum_Z * Sum_Z);
      begin
         if L > 1.0E-6 then
            Normal_X := Sum_X / L;
            Normal_Z := Sum_Z / L;
         else
            Normal_X := 0.0;
            Normal_Z := 0.0;
         end if;
      end;
   end Collide;

   function Loaded_Tiles return Natural is (Natural (Tiles.Length));

   function Segment_Distance (X, Z, AX, AZ, BX, BZ : Float) return Float is
      EX : constant Float := BX - AX;
      EZ : constant Float := BZ - AZ;
      L2 : constant Float := EX * EX + EZ * EZ;
      T  : Float := 0.0;
   begin
      if L2 > 1.0E-8 then
         T := Float'Max (0.0, Float'Min (1.0, ((X - AX) * EX + (Z - AZ) * EZ) / L2));
      end if;
      return Sqrt ((X - AX - T * EX) ** 2 + (Z - AZ - T * EZ) ** 2);
   end Segment_Distance;

   --  Visit the loaded tiles touched by the square of half-size R around
   --  (X, Z).  Every edge and road strip is stored in each tile it crosses.
   generic
      with procedure Visit (Slot : Tile_Slot);
   procedure Around (X, Z, R : Float);

   procedure Around (X, Z, R : Float) is
   begin
      for TX in Geo.Tile_Of (Long_Float (X - R)) .. Geo.Tile_Of (Long_Float (X + R)) loop
         for TZ in Geo.Tile_Of (Long_Float (Z - R)) .. Geo.Tile_Of (Long_Float (Z + R)) loop
            declare
               C : constant Tile_Maps.Cursor := Tiles.Find ((TX, TZ));
            begin
               if Tile_Maps.Has_Element (C) and then Tile_Maps.Element (C).Present then
                  Visit (Tile_Maps.Element (C));
               end if;
            end;
         end loop;
      end loop;
   end Around;

   function On_Road (X, Z : Float) return Boolean is
      Result : Boolean := False;
      Any    : Boolean := False;

      procedure Visit (Slot : Tile_Slot) is
         R : Float_Array renames Slot.Roads.all;
         I : Natural := R'First;
      begin
         Any := True;
         while not Result and then I + Floats_Per_Road - 1 <= R'Last loop
            if Segment_Distance (X, Z, R (I), R (I + 1), R (I + 2), R (I + 3)) < R (I + 4) then
               Result := True;
            end if;
            I := I + Floats_Per_Road;
         end loop;
      end Visit;

      procedure Check is new Around (Visit);
   begin
      Check (X, Z, 0.0);
      return Result or else not Any;   --  outside the map: treat as road
   end On_Road;

   function Roof_Below (X, Z, Below_Y : Float) return Float is
      Max_Heights : constant := 24;
      Heights : array (1 .. Max_Heights) of Float := (others => 0.0);
      Crossings : array (1 .. Max_Heights) of Natural := (others => 0);
      N : Natural := 0;
      procedure Visit (AX, AZ, BX, BZ, Bottom, Top : Float) is
         K : Natural := 0;
      begin
         if Top - Bottom < 2.0 or else Top > Below_Y + 0.3 then
            return;   --  a parapet, a kerb; or above you
         end if;
         for I in 1 .. N loop
            if abs (Heights (I) - Top) < 0.3 then
               K := I;
            end if;
         end loop;
         if K = 0 then
            if N = Max_Heights then
               return;
            end if;
            N := N + 1;
            Heights (N) := Top;
            K := N;
         end if;
         --  a ray from (X, Z) towards +X: does this wall cross it?
         if (AZ > Z) /= (BZ > Z) and then AX + (Z - AZ) / (BZ - AZ) * (BX - AX) > X then
            Crossings (K) := Crossings (K) + 1;
         end if;
      end Visit;
      procedure Each is new For_Walls_Near (Visit);
      Best : Float := -1.0E9;
   begin
      Each (X, Z, 90.0);
      for I in 1 .. N loop
         if Crossings (I) mod 2 = 1 and then Heights (I) > Best then
            Best := Heights (I);
         end if;
      end loop;
      return Best;
   end Roof_Below;

   function Obstacle_At (X, Y, Z, Radius : Float; Up_Down : Float := -1.0) return Boolean is
      Result : Boolean := False;
      V : constant Float := (if Up_Down < 0.0 then Radius else Up_Down);   --  (how far up and down)

      procedure Visit (Slot : Tile_Slot) is
         E : Float_Array renames Slot.Edges.all;
         I : Natural := E'First;
      begin
         while not Result and then I + Floats_Per_Edge - 1 <= E'Last loop
            if Y >= E (I + 4) - V and then Y <= E (I + 5) + V
              and then Segment_Distance (X, Z, E (I), E (I + 1), E (I + 2), E (I + 3)) < Radius
            then
               Result := True;
            end if;
            I := I + Floats_Per_Edge;
         end loop;
      end Visit;

      procedure Check is new Around (Visit);
   begin
      Check (X, Z, Radius);
      return Result;
   end Obstacle_At;

   procedure Nearest_Lights
     (X, Z : Float; Data : out Light_Data; Count : out Natural)
   is
      Best_D : array (0 .. Max_Lights - 1) of Float := (others => Float'Last);
      Worst  : Natural := 0;
   begin
      Data := (others => 0.0);
      Count := 0;
      for Slot of Tiles loop
         if Slot.Present and then Slot.Lights /= null then
            declare
               L : Float_Array renames Slot.Lights.all;
               I : Natural := L'First;
            begin
               while I + 2 <= L'Last loop
                  declare
                     D : constant Float := (L (I) - X) ** 2 + (L (I + 2) - Z) ** 2;
                  begin
                     if D < Best_D (Worst) then
                        Best_D (Worst) := D;
                        Data (4 * Worst) := L (I);
                        Data (4 * Worst + 1) := L (I + 1);
                        Data (4 * Worst + 2) := L (I + 2);
                        Data (4 * Worst + 3) := 1.0;
                        Count := Natural'Min (Max_Lights, Count + 1);
                        for K in Best_D'Range loop
                           if Best_D (K) > Best_D (Worst) then
                              Worst := K;
                           end if;
                        end loop;
                     end if;
                  end;
                  I := I + 3;
               end loop;
            end;
         end if;
      end loop;
   end Nearest_Lights;

end World;
