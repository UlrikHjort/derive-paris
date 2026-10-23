--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Containers.Generic_Array_Sort;
with Ada.Directories;
with Ada.Containers.Hashed_Maps;
with Ada.Containers.Vectors;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Numerics.Long_Elementary_Functions;
with Ada.Text_IO;
with Interfaces;

with Earcut;
with Geo;
with Terrain;
with Tile_IO;

package body World_Builder is

   use Osm_Model;
   use Ada.Numerics.Long_Elementary_Functions;
   use Tile_IO;
   use type Ada.Containers.Count_Type;
   use type Interfaces.Unsigned_32;

   ---------------------------------------------------------------------------
   --  Geometry types
   ---------------------------------------------------------------------------

   type P2 is record
      X, Z : Long_Float;
   end record;

   type V3 is record
      X, Y, Z : Long_Float;
   end record;

   function "+" (A, B : V3) return V3 is (A.X + B.X, A.Y + B.Y, A.Z + B.Z);
   function "-" (A, B : V3) return V3 is (A.X - B.X, A.Y - B.Y, A.Z - B.Z);
   function "*" (S : Long_Float; A : V3) return V3 is (S * A.X, S * A.Y, S * A.Z);
   function Dot (A, B : V3) return Long_Float is (A.X * B.X + A.Y * B.Y + A.Z * B.Z);
   function Cross (A, B : V3) return V3 is
     (A.Y * B.Z - A.Z * B.Y, A.Z * B.X - A.X * B.Z, A.X * B.Y - A.Y * B.X);
   function Normalize (A : V3) return V3 is
     (if Dot (A, A) > 1.0E-24 then (1.0 / Sqrt (Dot (A, A))) * A
      else (0.0, 1.0, 0.0));

   package Ring_Pkg is new Ada.Containers.Vectors (Natural, P2);
   subtype Ring is Ring_Pkg.Vector;

   package Ring_Vectors is new Ada.Containers.Vectors
     (Natural, Ring, Ring_Pkg."=");

   type Poly is record
      Outer : Ring;
      Holes : Ring_Vectors.Vector;
   end record;

   package Poly_Vectors is new Ada.Containers.Vectors (Natural, Poly);

   package Id_Vec_Vectors is new Ada.Containers.Vectors
     (Natural, Id_Vectors.Vector, Id_Vectors."=");

   ---------------------------------------------------------------------------
   --  Materials (must match shaders/world.frag)
   ---------------------------------------------------------------------------

   Mat_Pavement   : constant := 0.0;
   Mat_Asphalt    : constant := 1.0;
   Mat_Curb       : constant := 2.0;
   Mat_Path       : constant := 3.0;
   Mat_Grass      : constant := 4.0;
   Mat_Park_Sand  : constant := 5.0;
   Mat_Water      : constant := 6.0;
   Mat_Wood       : constant := 7.0;
   Mat_Square     : constant := 8.0;
   Mat_Parking    : constant := 9.0;
   Mat_Wall       : constant := 10.0;
   Mat_Mansard    : constant := 11.0;
   Mat_Roof       : constant := 12.0;
   Mat_Trunk      : constant := 13.0;
   Mat_Crown      : constant := 14.0;
   Mat_Flowerbed  : constant := 20.0;
   Mat_Paint      : constant := 21.0;
   Mat_Quay       : constant := 22.0;
   Mat_Chimney    : constant := 23.0;
   Mat_Pots       : constant := 24.0;
   Mat_Dome       : constant := 25.0;
   Mat_Lamp_Post  : constant := 26.0;
   Mat_Lantern    : constant := 27.0;
   Mat_Signal     : constant := 28.0;   --  traffic light lamp, uv = (offset, group)
   Mat_Gilt       : constant := 48.0;   --  gilded bronze
   Mat_Verdigris  : constant := 83.0;   --  copper gone green
   Mat_Stone      : constant := 29.0;   --  dressed stone of monuments, uv in metres
   Mat_Lattice    : constant := 33.0;   --  wrought-iron lattice (Eiffel Tower)
   Mat_Railing    : constant := 34.0;   --  balcony railing, uv in metres
   Mat_Parquet    : constant := 35.0;   --  herringbone parquet, uv in metres
   Mat_Plaster    : constant := 36.0;   --  painted plaster inside
   Mat_Glass_Pane : constant := 16.0;   --  glass (as on the cars)

   Water_Level    : constant := -6.0;   --  the Seine below the quays
   Low_Level      : constant := -3.8;   --  the lower quays (bas-ports)

   --  Building styles, stored in the integer part of the seed
   Style_Haussmann : constant := 0.0;
   Style_Monument  : constant := 1.0;
   Style_Small     : constant := 2.0;
   Style_Boat      : constant := 3.0;
   Style_Glass     : constant := 4.0;   --  glass or metal curtain wall

   ---------------------------------------------------------------------------
   --  State
   ---------------------------------------------------------------------------

   Model_Ref : access constant Model;

   DX0, DX1, DZ0, DZ1 : Long_Float;    --  data rectangle in local metres
   TX0, TX1, TZ0, TZ1 : Integer;       --  tile range

   package Float_Vectors is new Ada.Containers.Vectors (Natural, Float);
   package U32_Vectors is new Ada.Containers.Vectors
     (Natural, Interfaces.Unsigned_32);

   type Index_Lists is array (Group_Id) of U32_Vectors.Vector;

   --  Ground vertices are shared between triangles (they only differ by
   --  position, material and seed), which keeps ribbons and areas small.
   type Vertex_Key is record
      X, Y, Z, Mat, Seed : Integer;
   end record;

   function Hash_Key (K : Vertex_Key) return Ada.Containers.Hash_Type is
      use Interfaces;
      H : Unsigned_32 := Unsigned_32'Mod (K.X);
   begin
      H := (H * 16777619) xor Unsigned_32'Mod (K.Z);
      H := (H * 16777619) xor Unsigned_32'Mod (K.Y);
      H := (H * 16777619) xor Unsigned_32'Mod (K.Mat);
      H := (H * 16777619) xor Unsigned_32'Mod (K.Seed);
      return Ada.Containers.Hash_Type (H);
   end Hash_Key;

   package Vertex_Maps is new Ada.Containers.Hashed_Maps
     (Vertex_Key, Interfaces.Unsigned_32, Hash_Key, "=", Interfaces."=");

   type Tile_Builder is record
      Verts  : Float_Vectors.Vector;
      Idx    : Index_Lists;
      Edges  : Float_Vectors.Vector;
      Lights : Float_Vectors.Vector;
      Roads  : Float_Vectors.Vector;
      Shared : Vertex_Maps.Map;
   end record;

   type Tile_Builder_Access is access Tile_Builder;
   type Tile_Grid is array (Integer range <>, Integer range <>)
     of Tile_Builder_Access;
   type Tile_Grid_Access is access Tile_Grid;

   Grid : Tile_Grid_Access;

   function Tile (TX, TZ : Integer) return Tile_Builder_Access is
   begin
      if Grid (TX, TZ) = null then
         Grid (TX, TZ) := new Tile_Builder;
      end if;
      return Grid (TX, TZ);
   end Tile;

   function In_Data (X, Z : Long_Float) return Boolean is
     (X >= DX0 and then X < DX1 and then Z >= DZ0 and then Z < DZ1);

   --  Buildings this close outside the data rectangle (a neighbouring chunk)
   --  still give collision edges and party walls, so chunks fit seamlessly
   Margin : constant := 200.0;

   function In_Margin (X, Z : Long_Float) return Boolean is
     (X >= DX0 - Margin and then X < DX1 + Margin
      and then Z >= DZ0 - Margin and then Z < DZ1 + Margin);

   function Hash01 (Id : Osm_Id; Salt : Natural := 0) return Long_Float is
      use Interfaces;
      H : Unsigned_64 := Unsigned_64 (Id mod 2**62) xor Unsigned_64 (Salt * 7919);
   begin
      H := (H xor Shift_Right (H, 33)) * 16#FF51AFD7ED558CCD#;
      H := (H xor Shift_Right (H, 33)) * 16#C4CEB9FE1A85EC53#;
      H := H xor Shift_Right (H, 33);
      return Long_Float (H mod 1_000_000) / 1_000_000.0;
   end Hash01;

   ---------------------------------------------------------------------------
   --  Vertex emission
   ---------------------------------------------------------------------------

   --  Roof colour of the building being emitted (0 = default), packed as
   --  1 + r * 1024 + g * 32 + b with 5 bits per channel.  Roof and dome
   --  vertices carry it in their v coordinate, which their shaders do not
   --  otherwise use.
   Current_Roof_Colour : Long_Float := 0.0;

   ---------------------------------------------------------------------------
   --  Hills: everything is built as if the city were flat and lifted onto
   --  the ground as it is emitted.  Small things follow the ground; a
   --  building stands level on the highest point of its plot, its walls
   --  reaching down to the ground on the lower side.
   ---------------------------------------------------------------------------

   type Lift_Kind is (Follow, Block);
   Lift_Mode  : Lift_Kind := Follow;
   Block_Base : Long_Float := 0.0;

   function Lift_Y (X, Y, Z : Long_Float) return Long_Float is
     (if Lift_Mode = Follow then Y + Terrain.Height (X, Z)
      elsif Y <= 0.01 then Long_Float'Min (Block_Base, Terrain.Height (X, Z)) + Y
      else Y + Block_Base);

   procedure Stand_On (Outer : Ring) is
   begin
      Lift_Mode := Block;
      Block_Base := Long_Float'First;
      for P of Outer loop
         Block_Base := Long_Float'Max (Block_Base, Terrain.Height (P.X, P.Z));
      end loop;
      if Block_Base = Long_Float'First then
         Block_Base := 0.0;
      end if;
   end Stand_On;

   procedure Follow_Ground is
   begin
      Lift_Mode := Follow;
      Block_Base := 0.0;
   end Follow_Ground;

   function Put_Vertex
     (T : in out Tile_Builder; P, N : V3; U, V, Mat, Seed : Long_Float)
      return Interfaces.Unsigned_32
   is
      Index : constant Interfaces.Unsigned_32 :=
        Interfaces.Unsigned_32 (Natural (T.Verts.Length) / Floats_Per_Vertex);
      VV    : constant Long_Float :=
        (if Mat = Mat_Roof or else Mat = Mat_Dome then Current_Roof_Colour else V);
   begin
      T.Verts.Append (Float (P.X));
      T.Verts.Append (Float (P.Y));
      T.Verts.Append (Float (P.Z));
      T.Verts.Append (Float (N.X));
      T.Verts.Append (Float (N.Y));
      T.Verts.Append (Float (N.Z));
      T.Verts.Append (Float (U));
      T.Verts.Append (Float (VV));
      T.Verts.Append (Float (Mat));
      T.Verts.Append (Float (Seed));
      return Index;
   end Put_Vertex;

   function Add_Vertex
     (T : in out Tile_Builder; P, N : V3; U, V, Mat, Seed : Long_Float)
      return Interfaces.Unsigned_32
   is (Put_Vertex (T, (P.X, Lift_Y (P.X, P.Y, P.Z), P.Z), N, U, V, Mat, Seed));

   procedure Tri
     (T : in out Tile_Builder; G : Group_Id; A, B, C : Interfaces.Unsigned_32) is
   begin
      T.Idx (G).Append (A);
      T.Idx (G).Append (B);
      T.Idx (G).Append (C);
   end Tri;

   procedure Solid_Quad
     (T              : in out Tile_Builder;
      P0, P1, P2, P3 : V3;
      N              : V3;
      U0, U1, V0, V1 : Long_Float;
      Mat, Seed      : Long_Float)
   is
      I0 : constant Interfaces.Unsigned_32 := Add_Vertex (T, P0, N, U0, V0, Mat, Seed);
      I1 : constant Interfaces.Unsigned_32 := Add_Vertex (T, P1, N, U1, V0, Mat, Seed);
      I2 : constant Interfaces.Unsigned_32 := Add_Vertex (T, P2, N, U1, V1, Mat, Seed);
      I3 : constant Interfaces.Unsigned_32 := Add_Vertex (T, P3, N, U0, V1, Mat, Seed);
   begin
      Tri (T, Solid, I0, I1, I2);
      Tri (T, Solid, I0, I2, I3);
   end Solid_Quad;

   ---------------------------------------------------------------------------
   --  Ground triangles, clipped to tile and data rectangles
   ---------------------------------------------------------------------------

   type P2_Array is array (1 .. 16) of P2;

   procedure Clip_Rect
     (Poly_In : P2_Array; N_In : Natural;
      X0, X1, Z0, Z1 : Long_Float;
      Poly_Out : out P2_Array; N_Out : out Natural)
   is
      A  : P2_Array := Poly_In;
      NA : Natural := N_In;
      B  : P2_Array;
      NB : Natural;

      procedure Plane (Side : Positive) is
         function D (P : P2) return Long_Float is
           (case Side is
               when 1 => P.X - X0,
               when 2 => X1 - P.X,
               when 3 => P.Z - Z0,
               when others => Z1 - P.Z);
         S, E   : P2;
         DS, DE : Long_Float;
      begin
         NB := 0;
         if NA = 0 then
            return;
         end if;
         S := A (NA);
         for I in 1 .. NA loop
            E := A (I);
            DS := D (S);
            DE := D (E);
            if DE >= 0.0 then
               if DS < 0.0 then
                  NB := NB + 1;
                  B (NB) := (S.X + (E.X - S.X) * DS / (DS - DE),
                             S.Z + (E.Z - S.Z) * DS / (DS - DE));
               end if;
               NB := NB + 1;
               B (NB) := E;
            elsif DS >= 0.0 then
               NB := NB + 1;
               B (NB) := (S.X + (E.X - S.X) * DS / (DS - DE),
                          S.Z + (E.Z - S.Z) * DS / (DS - DE));
            end if;
            S := E;
         end loop;
         A := B;
         NA := NB;
      end Plane;
   begin
      for Side in 1 .. 4 loop
         Plane (Side);
      end loop;
      Poly_Out := A;
      N_Out := NA;
   end Clip_Rect;

   --  Ground vertices lie on the hills, with the hills' normal
   function Ground_Vertex
     (T : in out Tile_Builder; X, Y, Z, Mat, Seed : Long_Float)
      return Interfaces.Unsigned_32
   is
      K : constant Vertex_Key :=
        (Integer (X * 1000.0), Integer (Y * 1000.0), Integer (Z * 1000.0),
         Integer (Mat), Integer (Seed * 1.0E6));
      C : constant Vertex_Maps.Cursor := T.Shared.Find (K);
      I : Interfaces.Unsigned_32;
      E : constant := 2.0;
      GX : constant Long_Float := (Terrain.Height (X + E, Z) - Terrain.Height (X - E, Z)) / (2.0 * E);
      GZ : constant Long_Float := (Terrain.Height (X, Z + E) - Terrain.Height (X, Z - E)) / (2.0 * E);
   begin
      if Vertex_Maps.Has_Element (C) then
         return Vertex_Maps.Element (C);
      end if;
      I := Put_Vertex (T, (X, Y + Terrain.Height (X, Z), Z), Normalize ((-GX, 1.0, -GZ)),
                       X, Z, Mat, Seed);
      T.Shared.Insert (K, I);
      return I;
   end Ground_Vertex;

   procedure Ground_Tri
     (G : Group_Id; Mat, Seed : Long_Float; A, B, C : P2; Y : Long_Float := 0.0)
   is
      Min_X : constant Long_Float := Long_Float'Min (A.X, Long_Float'Min (B.X, C.X));
      Max_X : constant Long_Float := Long_Float'Max (A.X, Long_Float'Max (B.X, C.X));
      Min_Z : constant Long_Float := Long_Float'Min (A.Z, Long_Float'Min (B.Z, C.Z));
      Max_Z : constant Long_Float := Long_Float'Max (A.Z, Long_Float'Max (B.Z, C.Z));
      Input : P2_Array;
      Clipped : P2_Array;
      N     : Natural;
   begin
      if Max_X < DX0 or else Min_X > DX1 or else Max_Z < DZ0 or else Min_Z > DZ1
      then
         return;
      end if;
      Input (1) := A;
      Input (2) := B;
      Input (3) := C;
      for TX in Integer'Max (TX0, Geo.Tile_Of (Min_X))
             .. Integer'Min (TX1, Geo.Tile_Of (Max_X))
      loop
         for TZ in Integer'Max (TZ0, Geo.Tile_Of (Min_Z))
                .. Integer'Min (TZ1, Geo.Tile_Of (Max_Z))
         loop
            Clip_Rect
              (Input, 3,
               Long_Float'Max (DX0, Long_Float (TX) * Geo.Tile_Size),
               Long_Float'Min (DX1, Long_Float (TX + 1) * Geo.Tile_Size),
               Long_Float'Max (DZ0, Long_Float (TZ) * Geo.Tile_Size),
               Long_Float'Min (DZ1, Long_Float (TZ + 1) * Geo.Tile_Size),
               Clipped, N);
            if N >= 3 then
               declare
                  T : Tile_Builder renames Tile (TX, TZ).all;

                  --  An edge is split where the ground bends under it.  The
                  --  test only looks at the edge, so both triangles that
                  --  share it split it the same way: no cracks.
                  function Dist (A, B : P2) return Long_Float is
                    (Sqrt ((A.X - B.X) ** 2 + (A.Z - B.Z) ** 2));

                  function Split_Edge (A, B : P2) return Boolean is
                     L : constant Long_Float := Dist (A, B);
                  begin
                     if L < 3.0 then
                        return False;
                     elsif L > 60.0 then
                        return True;
                     end if;
                     declare
                        M : constant P2 := ((A.X + B.X) / 2.0, (A.Z + B.Z) / 2.0);
                     begin
                        return abs (Terrain.Height (M.X, M.Z)
                                    - (Terrain.Height (A.X, A.Z) + Terrain.Height (B.X, B.Z)) / 2.0)
                          > 0.05;
                     end;
                  end Split_Edge;

                  procedure Drape (A, B, C : P2; Depth : Natural) is
                     SA : constant Boolean := Depth < 12 and then Split_Edge (B, C);
                     SB : constant Boolean := Depth < 12 and then Split_Edge (C, A);
                     SC : constant Boolean := Depth < 12 and then Split_Edge (A, B);
                  begin
                     if not (SA or else SB or else SC) then
                        declare
                           IA : constant Interfaces.Unsigned_32 := Ground_Vertex (T, A.X, Y, A.Z, Mat, Seed);
                           IB : constant Interfaces.Unsigned_32 := Ground_Vertex (T, B.X, Y, B.Z, Mat, Seed);
                           IC : constant Interfaces.Unsigned_32 := Ground_Vertex (T, C.X, Y, C.Z, Mat, Seed);
                        begin
                           if IA /= IB and then IB /= IC and then IA /= IC then
                              Tri (T, G, IA, IB, IC);
                           end if;
                        end;
                        return;
                     end if;
                     --  split the longest of the edges that need it
                     declare
                        LA : constant Long_Float := (if SA then Dist (B, C) else -1.0);
                        LB : constant Long_Float := (if SB then Dist (C, A) else -1.0);
                        LC : constant Long_Float := (if SC then Dist (A, B) else -1.0);
                     begin
                        if LA >= LB and then LA >= LC then
                           declare
                              M : constant P2 := ((B.X + C.X) / 2.0, (B.Z + C.Z) / 2.0);
                           begin
                              Drape (A, B, M, Depth + 1);
                              Drape (A, M, C, Depth + 1);
                           end;
                        elsif LB >= LC then
                           declare
                              M : constant P2 := ((C.X + A.X) / 2.0, (C.Z + A.Z) / 2.0);
                           begin
                              Drape (B, C, M, Depth + 1);
                              Drape (B, M, A, Depth + 1);
                           end;
                        else
                           declare
                              M : constant P2 := ((A.X + B.X) / 2.0, (A.Z + B.Z) / 2.0);
                           begin
                              Drape (C, A, M, Depth + 1);
                              Drape (C, M, B, Depth + 1);
                           end;
                        end if;
                     end;
                  end Drape;
               begin
                  for I in 3 .. N loop
                     Drape (Clipped (1), Clipped (I - 1), Clipped (I), 0);
                  end loop;
               end;
            end if;
         end loop;
      end loop;
   end Ground_Tri;

   ---------------------------------------------------------------------------
   --  Rings and polygons
   ---------------------------------------------------------------------------

   function Signed_Area (R : Ring) return Long_Float is
      S : Long_Float := 0.0;
      N : constant Natural := Natural (R.Length);
   begin
      for I in 0 .. N - 1 loop
         declare
            A : constant P2 := R (I);
            B : constant P2 := R ((I + 1) mod N);
         begin
            S := S + (A.X * B.Z - B.X * A.Z);
         end;
      end loop;
      return S / 2.0;
   end Signed_Area;

   procedure Orient (R : in out Ring; Positive_Area : Boolean) is
   begin
      if (Signed_Area (R) > 0.0) /= Positive_Area then
         R.Reverse_Elements;
      end if;
   end Orient;

   function Point_In_Ring (P : P2; R : Ring) return Boolean is
      Inside : Boolean := False;
      N      : constant Natural := Natural (R.Length);
      J      : Natural := N - 1;
   begin
      for I in 0 .. N - 1 loop
         declare
            A : constant P2 := R (I);
            B : constant P2 := R (J);
         begin
            if (A.Z > P.Z) /= (B.Z > P.Z)
              and then P.X < (B.X - A.X) * (P.Z - A.Z) / (B.Z - A.Z) + A.X
            then
               Inside := not Inside;
            end if;
         end;
         J := I;
      end loop;
      return Inside;
   end Point_In_Ring;

   function Ids_To_Ring (Ids : Id_Vectors.Vector; R : out Ring) return Boolean
   is
      X, Z : Long_Float;
   begin
      R.Clear;
      for Id of Ids loop
         declare
            C : constant Node_Maps.Cursor := Model_Ref.Nodes.Find (Id);
         begin
            if not Node_Maps.Has_Element (C) then
               return False;
            end if;
            Geo.To_Local (Node_Maps.Element (C).Lat, Node_Maps.Element (C).Lon,
                          X, Z);
            if R.Is_Empty or else (R.Last_Element.X /= X
                                   or else R.Last_Element.Z /= Z)
            then
               R.Append ((X, Z));
            end if;
         end;
      end loop;
      if R.Length >= 2 and then R.First_Element = R.Last_Element then
         R.Delete_Last;
      end if;
      return R.Length >= 3;
   end Ids_To_Ring;

   function Is_Closed (Ids : Id_Vectors.Vector) return Boolean is
     (Ids.Length >= 4 and then Ids.First_Element = Ids.Last_Element);

   procedure Stitch
     (Parts : in out Id_Vec_Vectors.Vector; Rings : in out Ring_Vectors.Vector)
   is
      Cur      : Id_Vectors.Vector;
      Found    : Boolean;
      Reversed : Boolean;
      R        : Ring;
   begin
      while not Parts.Is_Empty loop
         Cur := Parts.Last_Element;
         Parts.Delete_Last;
         Reversed := False;
         while Cur.Length >= 2 and then not Is_Closed (Cur) loop
            Found := False;
            for K in Parts.First_Index .. Parts.Last_Index loop
               declare
                  P : constant Id_Vectors.Vector := Parts (K);
               begin
                  if P.Length >= 2 then
                     if P.First_Element = Cur.Last_Element then
                        for J in P.First_Index + 1 .. P.Last_Index loop
                           Cur.Append (P (J));
                        end loop;
                        Found := True;
                     elsif P.Last_Element = Cur.Last_Element then
                        for J in reverse P.First_Index .. P.Last_Index - 1 loop
                           Cur.Append (P (J));
                        end loop;
                        Found := True;
                     end if;
                  end if;
               end;
               if Found then
                  Parts.Delete (K);
                  exit;
               end if;
            end loop;
            if Found then
               Reversed := False;
            elsif Reversed then
               exit;
            else
               Cur.Reverse_Elements;
               Reversed := True;
            end if;
         end loop;
         if Is_Closed (Cur) and then Ids_To_Ring (Cur, R) then
            Rings.Append (R);
         end if;
      end loop;
   end Stitch;

   procedure Relation_Polys (Rel : Rel_Rec; Polys : out Poly_Vectors.Vector) is
      Outer_Parts, Inner_Parts : Id_Vec_Vectors.Vector;
      Outers, Inners           : Ring_Vectors.Vector;
   begin
      Polys.Clear;
      for Mem of Rel.Members loop
         if Mem.Is_Way and then Mem.Role /= Other
           and then Model_Ref.Way_Index.Contains (Mem.Ref)
         then
            declare
               Refs : constant Id_Vectors.Vector :=
                 Model_Ref.Ways (Model_Ref.Way_Index (Mem.Ref)).Refs;
            begin
               if Mem.Role = Outer then
                  Outer_Parts.Append (Refs);
               else
                  Inner_Parts.Append (Refs);
               end if;
            end;
         end if;
      end loop;
      Stitch (Outer_Parts, Outers);
      Stitch (Inner_Parts, Inners);
      for O of Outers loop
         declare
            P : Poly;
         begin
            P.Outer := O;
            Orient (P.Outer, True);
            Polys.Append (P);
         end;
      end loop;
      for H of Inners loop
         for P of Polys loop
            if Point_In_Ring (H.First_Element, P.Outer) then
               declare
                  Hole : Ring := H;
               begin
                  Orient (Hole, False);
                  P.Holes.Append (Hole);
               end;
               exit;
            end if;
         end loop;
      end loop;
   end Relation_Polys;

   procedure Bounds (R : Ring; X0, X1, Z0, Z1 : out Long_Float) is
   begin
      X0 := Long_Float'Last;
      X1 := Long_Float'First;
      Z0 := Long_Float'Last;
      Z1 := Long_Float'First;
      for P of R loop
         X0 := Long_Float'Min (X0, P.X);
         X1 := Long_Float'Max (X1, P.X);
         Z0 := Long_Float'Min (Z0, P.Z);
         Z1 := Long_Float'Max (Z1, P.Z);
      end loop;
   end Bounds;

   function Touches_Data (R : Ring) return Boolean is
      X0, X1, Z0, Z1 : Long_Float;
   begin
      Bounds (R, X0, X1, Z0, Z1);
      return X1 >= DX0 and then X0 <= DX1 and then Z1 >= DZ0 and then Z0 <= DZ1;
   end Touches_Data;

   function Centroid (R : Ring) return P2 is
      SX, SZ : Long_Float := 0.0;
   begin
      for P of R loop
         SX := SX + P.X;
         SZ := SZ + P.Z;
      end loop;
      return (SX / Long_Float (R.Length), SZ / Long_Float (R.Length));
   end Centroid;

   procedure Triangulate (P : Poly; Pts : out Earcut.Point_Array;
                          Tris : out Earcut.Index_Vectors.Vector)
   is
      Hole_Starts : Earcut.Natural_Array (1 .. Natural (P.Holes.Length));
      K           : Natural := 0;
   begin
      for Pt of P.Outer loop
         Pts (K) := (Pt.X, Pt.Z);
         K := K + 1;
      end loop;
      for H in Hole_Starts'Range loop
         Hole_Starts (H) := K;
         for Pt of P.Holes (H - 1) loop
            Pts (K) := (Pt.X, Pt.Z);
            K := K + 1;
         end loop;
      end loop;
      Earcut.Triangulate (Pts, Hole_Starts, Tris);
   end Triangulate;

   function Point_Count (P : Poly) return Natural is
      N : Natural := Natural (P.Outer.Length);
   begin
      for H of P.Holes loop
         N := N + Natural (H.Length);
      end loop;
      return N;
   end Point_Count;

   ---------------------------------------------------------------------------
   --  Tag helpers
   ---------------------------------------------------------------------------

   function Num_Value (S : String) return Long_Float;

   function Num (Tags : Tag_Maps.Map; Key : String) return Long_Float is
     (Num_Value (Tag (Tags, Key)));

   --  Leading number of a tag value ("12", "12.5 m", "3,5"), -1 if none
   function Num_Value (S : String) return Long_Float is
      Buf  : String (1 .. S'Length + 2);
      Last : Natural := 1;
   begin
      Buf (1) := '0';
      for C of S loop
         exit when not (C in '0' .. '9' or else C = '.' or else C = ',');
         Last := Last + 1;
         Buf (Last) := (if C = ',' then '.' else C);
      end loop;
      if Last = 1 then
         return -1.0;
      end if;
      if Buf (Last) = '.' then
         Last := Last - 1;
      end if;
      return Long_Float'Value (Buf (1 .. Last));
   exception
      when Constraint_Error =>
         return -1.0;
   end Num_Value;

   function One_Of (S : String; List : String) return Boolean is
     (S'Length > 0
      and then (for some I in List'First .. List'Last - S'Length + 1 =>
                  List (I .. I + S'Length - 1) = S
                  and then (I = List'First or else List (I - 1) = '|')
                  and then (I + S'Length - 1 = List'Last
                            or else List (I + S'Length) = '|')));

   function Area_Material (Tags : Tag_Maps.Map) return Long_Float is
      Natural_V : constant String := Tag (Tags, "natural");
      Landuse   : constant String := Tag (Tags, "landuse");
      Leisure   : constant String := Tag (Tags, "leisure");
   begin
      --  underground (a canal under a boulevard): nothing to see
      if (Has (Tags, "tunnel") and then Tag (Tags, "tunnel") /= "no")
        or else Tag (Tags, "location") = "underground"
      then
         return -1.0;
      end if;
      if Natural_V = "water" or else Tag (Tags, "waterway") = "riverbank"
        or else Leisure = "swimming_pool" or else Tag (Tags, "amenity") = "fountain"
      then
         return Mat_Water;
      elsif Natural_V = "wood" or else Natural_V = "scrub" or else Landuse = "forest"
      then
         return Mat_Wood;
      elsif Landuse = "flowerbed" then
         return Mat_Flowerbed;
      elsif One_Of (Landuse, "grass|meadow|village_green|recreation_ground|greenfield|orchard")
        or else Natural_V = "grassland" or else Leisure = "pitch"
      then
         return Mat_Grass;
      elsif One_Of (Leisure, "park|garden|playground|schoolyard|dog_park") then
         return Mat_Park_Sand;
      elsif Has (Tags, "area:highway")
        or else (Has (Tags, "highway") and then Tag (Tags, "area") = "yes")
        or else Tag (Tags, "place") = "square"
        or else Tag (Tags, "man_made") = "bridge"
      then
         return Mat_Square;
      elsif Tag (Tags, "amenity") = "parking"
        and then not One_Of (Tag (Tags, "parking"), "underground|multi-storey")
      then
         return Mat_Parking;
      end if;
      return -1.0;
   end Area_Material;

   ---------------------------------------------------------------------------
   --  Features
   ---------------------------------------------------------------------------

   type Building is record
      Id        : Osm_Id;
      Shape     : Poly;
      Tags      : Tag_Maps.Map;
      Is_Part   : Boolean;
      Has_Parts : Boolean := False;
      Parts_Area : Long_Float := 0.0; --  how much of it its parts cover
      Sacred    : Boolean := False;   --  part of a church, cathedral...
      Edge_Only : Boolean := False;   --  in the margin: collision edges only
      Skip      : Boolean := False;   --  part of a landmark we model ourselves
      Center    : P2;
      X0, X1, Z0, Z1 : Long_Float;
   end record;

   package Building_Vectors is new Ada.Containers.Vectors (Natural, Building);

   type Area_Feature is record
      Shape : Poly;
      Mat   : Long_Float;
      Size  : Long_Float;
      Seed  : Long_Float;
      Group : Group_Id;
   end record;

   package Area_Vectors is new Ada.Containers.Vectors (Natural, Area_Feature);

   package Id_Lists is new Ada.Containers.Vectors (Natural, Osm_Id);

   type Line_Feature is record
      Pts    : Ring;
      Ids    : Id_Lists.Vector;    --  OSM node id of every point
      Width  : Long_Float;
      Group  : Group_Id;
      Mat    : Long_Float;
      Curb   : Boolean;
      Bridge : Boolean;
      Drive  : Boolean;            --  part of the traffic network
      Oneway : Integer;            --  0 two-way, 1 forward, -1 backward
      Lanes  : Natural;
      Limit  : Natural := 30;      --  maxspeed, km/h
      Name   : Ada.Strings.Unbounded.Unbounded_String;
      Kind   : Ada.Strings.Unbounded.Unbounded_String;   --  highway=*
      Layer  : Integer := 0;
      Low    : Boolean := False;   --  on the lower quays by the river
      Way_Id : Osm_Id := 0;
   end record;

   package Line_Vectors is new Ada.Containers.Vectors (Natural, Line_Feature);

   Buildings    : Building_Vectors.Vector;
   Areas        : Area_Vectors.Vector;
   Lines        : Line_Vectors.Vector;
   River_Polys  : Poly_Vectors.Vector;
   Bridge_Polys : Poly_Vectors.Vector;
   Marina_Polys : Poly_Vectors.Vector;   --  the river ports: lower quays

   type Landmark_Kind is (None, Lattice_Tower, Triumphal_Arch);

   function Landmark (Tags : Tag_Maps.Map) return Landmark_Kind is
      Name : constant String := Tag (Tags, "name");
   begin
      if Tag (Tags, "tower:construction") = "lattice" and then Num (Tags, "height") > 150.0
        and then Tag (Tags, "building") /= ""
      then
         return Lattice_Tower;
      elsif Name'Length >= 15 and then Name (Name'First .. Name'First + 14) = "Arc de Triomphe"
        and then Tag (Tags, "building") /= ""
      then
         return Triumphal_Arch;
      end if;
      return None;
   end Landmark;

   procedure Add_Building (Id : Osm_Id; P : Poly; Tags : Tag_Maps.Map;
                           Is_Part : Boolean)
   is
      B : Building;
   begin
      B.Id := Id;
      B.Shape := P;
      B.Tags := Tags;
      B.Is_Part := Is_Part;
      B.Center := Centroid (P.Outer);
      Bounds (P.Outer, B.X0, B.X1, B.Z0, B.Z1);
      B.Edge_Only := not In_Data (B.Center.X, B.Center.Z);
      if In_Margin (B.Center.X, B.Center.Z) then
         Buildings.Append (B);
      end if;
   end Add_Building;

   procedure Classify (Id : Osm_Id; Polys : Poly_Vectors.Vector;
                       Tags : Tag_Maps.Map)
   is
      Bld  : constant String := Tag (Tags, "building");
      Part : constant String := Tag (Tags, "building:part");
      Mat  : Long_Float;
      Lv   : constant String := Tag (Tags, "level");
      Ly   : constant String := Tag (Tags, "layer");
      --  rooms, stairs and halls under the street (the metro's under the
      --  Place de l'Opéra are mapped as building parts): nothing to build
      Below : constant Boolean :=
        (Tag (Tags, "indoor") /= "" and then Tag (Tags, "indoor") /= "no")
        or else Tag (Tags, "location") = "underground"
        or else (Tag (Tags, "tunnel") /= "" and then Tag (Tags, "tunnel") /= "no")
        or else (Lv'Length > 0 and then Lv (Lv'First) = '-')
        or else (Part /= "" and then Ly'Length > 0 and then Ly (Ly'First) = '-');
   begin
      if (Bld /= "" or else Part /= "") and then Below then
         null;
      elsif Bld /= "" and then Bld /= "no" then
         for P of Polys loop
            Add_Building (Id, P, Tags, False);
         end loop;
      elsif Part /= "" and then Part /= "no" then
         for P of Polys loop
            Add_Building (Id, P, Tags, True);
         end loop;
      else
         if Tag (Tags, "leisure") = "marina" then
            for P of Polys loop
               Marina_Polys.Append (P);
            end loop;
         end if;
         Mat := Area_Material (Tags);
         if Mat = Mat_Water
           and then (One_Of (Tag (Tags, "water"), "river|canal")
                     or else Tag (Tags, "waterway") = "riverbank")
         then
            for P of Polys loop
               if Touches_Data (P.Outer) then
                  River_Polys.Append (P);
               end if;
            end loop;
         elsif Mat >= 0.0 then
            for P of Polys loop
               if Touches_Data (P.Outer) then
                  declare
                     Size : Long_Float := abs Signed_Area (P.Outer);
                     Is_Bridge : constant Boolean := Tag (Tags, "man_made") = "bridge";
                  begin
                     for H of P.Holes loop
                        Size := Size - abs Signed_Area (H);
                     end loop;
                     Areas.Append ((P, Mat, Size, Hash01 (Id),
                                    (if Is_Bridge then Deck else Area)));
                     if Is_Bridge then
                        Bridge_Polys.Append (P);
                     end if;
                  end;
               end if;
            end loop;
         end if;
      end if;
   end Classify;

   --  maxspeed in km/h; without it the Paris rule: 30 almost everywhere
   --  since 2021, 20 in shared streets, 50 on the motorway-like roads
   function Speed_Limit (Tags : Tag_Maps.Map; HW : String) return Natural is
      V : constant String := Tag (Tags, "maxspeed");
      N : constant Long_Float := Num_Value (V);
   begin
      if V = "walk" or else V = "FR:walk" then
         return 10;
      elsif V = "FR:zone30" then
         return 30;
      elsif V = "FR:urban" then
         return 50;
      elsif N >= 5.0 and then N <= 130.0 then
         return Natural (N);
      elsif HW = "living_street" then
         return 20;
      elsif One_Of (HW, "motorway|trunk|motorway_link|trunk_link") then
         return 50;
      end if;
      return 30;
   end Speed_Limit;

   procedure Classify_Highway (W : Way_Rec) is
      HW    : constant String := Tag (W.Tags, "highway");
      Fw    : constant String := Tag (W.Tags, "footway");
      Width : Long_Float := -1.0;
      Group : Group_Id := Path;
      Mat   : Long_Float := Mat_Path;
      Curb  : Boolean := False;
      Pts   : Ring;
      Ids   : Id_Lists.Vector;
      X, Z  : Long_Float;
      Tagged_Width : constant Long_Float := Num (W.Tags, "width");
      Tagged_Lanes : constant Long_Float := Num (W.Tags, "lanes");
      OW    : constant String := Tag (W.Tags, "oneway");
      Oneway : Integer := 0;
      Lanes : Natural;
   begin
      if HW = "" or else Tag (W.Tags, "area") = "yes"
        or else (Has (W.Tags, "tunnel") and then Tag (W.Tags, "tunnel") /= "no")
        or else Tag (W.Tags, "indoor") = "yes"
        or else (Tag (W.Tags, "level")'Length > 0
                 and then Tag (W.Tags, "level") (Tag (W.Tags, "level")'First) = '-')
        or else One_Of (Fw, "sidewalk|crossing|traffic_island")
      then
         return;
      end if;

      if One_Of (HW, "motorway|trunk|primary") then
         Width := 13.0;
      elsif HW = "secondary" then
         Width := 11.0;
      elsif HW = "tertiary" then
         Width := 9.0;
      elsif One_Of (HW, "unclassified|residential") then
         Width := 6.5;
      elsif HW = "living_street" then
         Width := 5.5;
      elsif HW = "service" then
         Width := 4.0;
      end if;

      if Width > 0.0 then
         Group := Road;
         Mat := Mat_Asphalt;
         Curb := True;
         if Tagged_Width >= 3.0 and then Tagged_Width <= 30.0 then
            Width := Tagged_Width;
         end if;
      elsif HW = "pedestrian" then
         Width := 6.0;
         Mat := Mat_Square;
      elsif One_Of (HW, "footway|path|track|bridleway") then
         Width := 2.5;
      elsif HW = "steps" then
         Width := 2.5;
         Mat := Mat_Square;
      elsif HW = "cycleway" then
         Width := 2.0;
         Mat := Mat_Asphalt;
      else
         return;
      end if;

      for Id of W.Refs loop
         declare
            C : constant Node_Maps.Cursor := Model_Ref.Nodes.Find (Id);
         begin
            if Node_Maps.Has_Element (C) then
               Geo.To_Local (Node_Maps.Element (C).Lat, Node_Maps.Element (C).Lon,
                             X, Z);
               if Pts.Is_Empty or else Pts.Last_Element /= (X, Z) then
                  Pts.Append ((X, Z));
                  Ids.Append (Id);
               end if;
            end if;
         end;
      end loop;
      if Pts.Length < 2 or else not Touches_Data (Pts) then
         return;
      end if;

      if One_Of (OW, "yes|true|1") or else Tag (W.Tags, "junction") = "roundabout"
        or else One_Of (HW, "motorway|trunk")
      then
         Oneway := 1;
      elsif OW = "-1" then
         Oneway := -1;
      end if;
      if Tagged_Lanes >= 1.0 and then Tagged_Lanes <= 8.0 then
         Lanes := Natural (Tagged_Lanes);
      elsif Oneway /= 0 then
         Lanes := Natural'Max (1, Natural (Long_Float'Floor (Width / 4.5)));
      else
         Lanes := 2;
      end if;

      Lines.Append
        ((Pts    => Pts,
          Ids    => Ids,
          Width  => Width,
          Group  => Group,
          Mat    => Mat,
          Curb   => Curb,
          Bridge => Has (W.Tags, "bridge") and then Tag (W.Tags, "bridge") /= "no",
          Drive  => Group = Road and then HW /= "service"
                    and then Tag (W.Tags, "access") /= "no"
                    and then Tag (W.Tags, "motor_vehicle") /= "no",
          Oneway => Oneway,
          Lanes  => Lanes,
          Limit  => Speed_Limit (W.Tags, HW),
          Name   => Ada.Strings.Unbounded.To_Unbounded_String
                      (Tag (W.Tags, "name", Tag (W.Tags, "ref"))),
          Kind   => Ada.Strings.Unbounded.To_Unbounded_String (HW),
          Layer  => (if Tag (W.Tags, "layer") = "" then 0
                     elsif Tag (W.Tags, "layer") (Tag (W.Tags, "layer")'First) = '-'
                     then -1 else 1),
          Low    => False,
          Way_Id => W.Id));
   end Classify_Highway;

   procedure Collect_Features is
      Polys : Poly_Vectors.Vector;
      R     : Ring;
   begin
      for W of Model_Ref.Ways loop
         if Has (W.Tags, "highway") and then Tag (W.Tags, "area") /= "yes"
           and then not Has (W.Tags, "building")
         then
            Classify_Highway (W);
         elsif not W.Tags.Is_Empty and then Is_Closed (W.Refs)
           and then Ids_To_Ring (W.Refs, R)
         then
            Polys.Clear;
            declare
               P : Poly;
            begin
               P.Outer := R;
               Orient (P.Outer, True);
               Polys.Append (P);
            end;
            Classify (W.Id, Polys, W.Tags);
         end if;
      end loop;

      for Rel of Model_Ref.Rels loop
         if One_Of (Tag (Rel.Tags, "type"), "multipolygon|building") then
            Relation_Polys (Rel, Polys);
            Classify (Rel.Id, Polys, Rel.Tags);
         end if;
      end loop;

      --  A building whose outline contains building:parts is drawn through
      --  its parts only (the parts carry the detailed heights).  A part
      --  standing in one of its courtyards (a hole) is not its part, and
      --  the outline is only left out when the parts cover a good share of
      --  it: the Palais du Louvre has the Pyramid and the Arc du Carrousel
      --  in its courtyards, but its wings have no parts of their own.
      for Part of Buildings loop
         if Part.Is_Part then
            for B of Buildings loop
               if not B.Is_Part
                 and then Part.Center.X >= B.X0 and then Part.Center.X <= B.X1
                 and then Part.Center.Z >= B.Z0 and then Part.Center.Z <= B.Z1
                 and then Point_In_Ring (Part.Center, B.Shape.Outer)
                 and then (for all H of B.Shape.Holes => not Point_In_Ring (Part.Center, H))
               then
                  B.Parts_Area := B.Parts_Area + abs Signed_Area (Part.Shape.Outer);
                  if Landmark (B.Tags) /= None then
                     Part.Skip := True;
                  end if;
                  if One_Of (Tag (B.Tags, "building"),
                             "church|cathedral|chapel|basilica|temple|mosque|synagogue")
                  then
                     Part.Sacred := True;   --  (dressed stone, no flats' windows)
                  end if;
               end if;
            end loop;
         end if;
      end loop;

      for B of Buildings loop
         if not B.Is_Part and then B.Parts_Area > 0.0 then
            declare
               Net : Long_Float := abs Signed_Area (B.Shape.Outer);
            begin
               for H of B.Shape.Holes loop
                  Net := Net - abs Signed_Area (H);
               end loop;
               B.Has_Parts := B.Parts_Area >= 0.4 * Net;
            end;
         end if;
      end loop;

      --  Landmarks we model ourselves replace everything mapped inside
      --  their bounding box (the parts of the Eiffel Tower, its legs...)
      for L of Buildings loop
         if not L.Is_Part and then Landmark (L.Tags) /= None then
            for B of Buildings loop
               if B.Id /= L.Id
                 and then B.Center.X >= L.X0 - 2.0 and then B.Center.X <= L.X1 + 2.0
                 and then B.Center.Z >= L.Z0 - 2.0 and then B.Center.Z <= L.Z1 + 2.0
               then
                  B.Skip := True;
               end if;
            end loop;
         end if;
      end loop;
   end Collect_Features;

   ---------------------------------------------------------------------------
   --  Spatial queries
   ---------------------------------------------------------------------------

   function Point_In_Poly (P : P2; Pl : Poly) return Boolean is
   begin
      if not Point_In_Ring (P, Pl.Outer) then
         return False;
      end if;
      for H of Pl.Holes loop
         if Point_In_Ring (P, H) then
            return False;
         end if;
      end loop;
      return True;
   end Point_In_Poly;

   type Box is record
      X0, X1, Z0, Z1 : Long_Float;
   end record;

   package Box_Vectors is new Ada.Containers.Vectors (Natural, Box);
   River_Boxes : Box_Vectors.Vector;

   function In_River (P : P2) return Boolean is
   begin
      for I in River_Polys.First_Index .. River_Polys.Last_Index loop
         declare
            B : constant Box := River_Boxes (I);
         begin
            if P.X >= B.X0 and then P.X <= B.X1 and then P.Z >= B.Z0
              and then P.Z <= B.Z1 and then Point_In_Poly (P, River_Polys (I))
            then
               return True;
            end if;
         end;
      end loop;
      return False;
   end In_River;

   function Segment_Distance (P, A, B : P2) return Long_Float is
      Ex : constant Long_Float := B.X - A.X;
      Ez : constant Long_Float := B.Z - A.Z;
      L2 : constant Long_Float := Ex * Ex + Ez * Ez;
      T  : Long_Float := 0.0;
   begin
      if L2 > 1.0E-9 then
         T := Long_Float'Max (0.0, Long_Float'Min
                (1.0, ((P.X - A.X) * Ex + (P.Z - A.Z) * Ez) / L2));
      end if;
      return Sqrt ((P.X - A.X - T * Ex) ** 2 + (P.Z - A.Z - T * Ez) ** 2);
   end Segment_Distance;

   --  True when P is on (or within Margin of) a bridge deck
   function Near_Bridge (P : P2; Margin : Long_Float) return Boolean is
   begin
      for L of Lines loop
         if L.Bridge then
            for I in L.Pts.First_Index .. L.Pts.Last_Index - 1 loop
               if Segment_Distance (P, L.Pts (I), L.Pts (I + 1))
                 < L.Width / 2.0 + Margin
               then
                  return True;
               end if;
            end loop;
         end if;
      end loop;
      for B of Bridge_Polys loop
         if Point_In_Poly (P, B) then
            return True;
         end if;
      end loop;
      return False;
   end Near_Bridge;

   --  Building outlines bucketed in a coarse grid, for party-wall tests
   Cell_Size : constant := 30.0;

   type Cell_Key is record
      CX, CZ : Integer;
   end record;

   function Hash_Cell (K : Cell_Key) return Ada.Containers.Hash_Type is
     (Ada.Containers.Hash_Type ((K.CX * 92821 + K.CZ * 68917) mod 2**30));

   package Nat_Vectors is new Ada.Containers.Vectors (Natural, Natural);

   package Cell_Maps is new Ada.Containers.Hashed_Maps
     (Cell_Key, Nat_Vectors.Vector, Hash_Cell, "=", Nat_Vectors."=");

   Building_Grid : Cell_Maps.Map;

   function Cell_Of (C : Long_Float) return Integer is
     (Integer (Long_Float'Floor (C / Cell_Size)));

   procedure Index_Buildings is
   begin
      for I in Buildings.First_Index .. Buildings.Last_Index loop
         declare
            B : Building renames Buildings (I);
         begin
            if not B.Is_Part then
               for CX in Cell_Of (B.X0) .. Cell_Of (B.X1) loop
                  for CZ in Cell_Of (B.Z0) .. Cell_Of (B.Z1) loop
                     if not Building_Grid.Contains ((CX, CZ)) then
                        Building_Grid.Insert ((CX, CZ), Nat_Vectors.Empty_Vector);
                     end if;
                     Building_Grid ((CX, CZ)).Append (I);
                  end loop;
               end loop;
            end if;
         end;
      end loop;
   end Index_Buildings;

   function Building_At (P : P2; Except : Natural) return Integer is
      C : constant Cell_Maps.Cursor :=
        Building_Grid.Find ((Cell_Of (P.X), Cell_Of (P.Z)));
   begin
      if Cell_Maps.Has_Element (C) then
         for I of Cell_Maps.Element (C) loop
            if I /= Except then
               declare
                  B : Building renames Buildings (I);
               begin
                  if P.X >= B.X0 and then P.X <= B.X1 and then P.Z >= B.Z0
                    and then P.Z <= B.Z1 and then Point_In_Poly (P, B.Shape)
                  then
                     return I;
                  end if;
               end;
            end if;
         end loop;
      end if;
      return -1;
   end Building_At;

   ---------------------------------------------------------------------------
   --  Small solids
   ---------------------------------------------------------------------------

   type Quad_P2 is array (0 .. 3) of P2;

   function Edge_Out (A, B : P2) return P2 is
      Dx : constant Long_Float := B.X - A.X;
      Dz : constant Long_Float := B.Z - A.Z;
      L  : constant Long_Float := Long_Float'Max (Sqrt (Dx * Dx + Dz * Dz), 1.0E-9);
   begin
      return (Dz / L, -Dx / L);
   end Edge_Out;

   function "+" (A, B : P2) return P2 is (A.X + B.X, A.Z + B.Z);
   function "-" (A, B : P2) return P2 is (A.X - B.X, A.Z - B.Z);
   function "*" (S : Long_Float; A : P2) return P2 is (S * A.X, S * A.Z);
   function Dist (A, B : P2) return Long_Float is
     (Sqrt ((B.X - A.X) ** 2 + (B.Z - A.Z) ** 2));

   --  A vertical prism over a convex quadrilateral, sides and top
   procedure Prism
     (T : in out Tile_Builder; C : Quad_P2; Y0, Y1 : Long_Float;
      Mat, Seed : Long_Float; Top : Boolean := True)
   is
      Ctr : constant P2 := 0.25 * (C (0) + C (1) + C (2) + C (3));
   begin
      for I in 0 .. 3 loop
         declare
            A : constant P2 := C (I);
            B : constant P2 := C ((I + 1) mod 4);
            L : constant Long_Float := Dist (A, B);
            N : V3 := Normalize ((B.Z - A.Z, 0.0, -(B.X - A.X)));
         begin
            if L > 1.0E-4 then
               if N.X * (A.X - Ctr.X) + N.Z * (A.Z - Ctr.Z) < 0.0 then
                  N := (-N.X, 0.0, -N.Z);
               end if;
               Solid_Quad (T, (A.X, Y0, A.Z), (B.X, Y0, B.Z), (B.X, Y1, B.Z),
                           (A.X, Y1, A.Z), N, 0.0, L, Y0, Y1, Mat, Seed);
            end if;
         end;
      end loop;
      if Top then
         Solid_Quad (T, (C (0).X, Y1, C (0).Z), (C (1).X, Y1, C (1).Z),
                     (C (2).X, Y1, C (2).Z), (C (3).X, Y1, C (3).Z),
                     (0.0, 1.0, 0.0), 0.0, Dist (C (0), C (1)), 0.0,
                     Dist (C (1), C (2)), Mat, Seed);
      end if;
   end Prism;

   --  Rectangle from A to B, extending Depth to the side Side (unit)
   function Strip (A, B, Side : P2; Off, Depth : Long_Float) return Quad_P2 is
     (A + Off * Side, B + Off * Side, B + (Off + Depth) * Side,
      A + (Off + Depth) * Side);

   --  Collision edges go into every tile their bounding box touches, so
   --  the game only has to look at the tiles under a point
   --  Edges keep absolute heights (on the hills), like the geometry
   procedure Add_Edge (A, B : P2; Bottom : Long_Float := 0.0; Top : Long_Float := 1.0) is
      MX  : constant Long_Float := (A.X + B.X) / 2.0;
      MZ  : constant Long_Float := (A.Z + B.Z) / 2.0;
      Bot : constant Long_Float := Lift_Y (MX, Bottom, MZ);
      Tp  : constant Long_Float := Lift_Y (MX, Top, MZ);
   begin
      for TX in Integer'Max (TX0, Geo.Tile_Of (Long_Float'Min (A.X, B.X)))
             .. Integer'Min (TX1, Geo.Tile_Of (Long_Float'Max (A.X, B.X)))
      loop
         for TZ in Integer'Max (TZ0, Geo.Tile_Of (Long_Float'Min (A.Z, B.Z)))
                .. Integer'Min (TZ1, Geo.Tile_Of (Long_Float'Max (A.Z, B.Z)))
         loop
            declare
               T : Tile_Builder renames Tile (TX, TZ).all;
            begin
               T.Edges.Append (Float (A.X));
               T.Edges.Append (Float (A.Z));
               T.Edges.Append (Float (B.X));
               T.Edges.Append (Float (B.Z));
               T.Edges.Append (Float (Bot));
               T.Edges.Append (Float (Tp));
            end;
         end loop;
      end loop;
   end Add_Edge;

   function Tile_At (P : P2) return access Tile_Builder is
     (Tile (Geo.Tile_Of (P.X), Geo.Tile_Of (P.Z)));

   --  Walk a segment in pieces of about Step metres and call Run for each
   --  maximal stretch whose piece midpoints satisfy Keep.
   generic
      with function Keep (P : P2) return Boolean;
      with procedure Run (A, B : P2);
   procedure Split_Runs (A, B : P2; Step : Long_Float);

   procedure Split_Runs (A, B : P2; Step : Long_Float) is
      L      : constant Long_Float := Dist (A, B);
      N      : constant Positive := Positive'Max (1, Integer (Long_Float'Ceiling (L / Step)));
      In_Run : Boolean := False;
      Start  : P2 := A;
   begin
      for K in 0 .. N - 1 loop
         declare
            P0 : constant P2 := A + (Long_Float (K) / Long_Float (N)) * (B - A);
            P1 : constant P2 := A + (Long_Float (K + 1) / Long_Float (N)) * (B - A);
            Ok : constant Boolean := Keep (0.5 * (P0 + P1));
         begin
            if Ok and then not In_Run then
               Start := P0;
               In_Run := True;
            elsif not Ok and then In_Run then
               Run (Start, P0);
               In_Run := False;
            end if;
         end;
      end loop;
      if In_Run then
         Run (Start, B);
      end if;
   end Split_Runs;

   ---------------------------------------------------------------------------
   --  Buildings
   ---------------------------------------------------------------------------

   Floor_Height   : constant := 3.1;
   Mansard_Height : constant := 2.8;
   Mansard_Inset  : constant := 1.1;

   type Dist_Array is array (Natural range <>) of Long_Float;
   type Bool_Array is array (Natural range <>) of Boolean;

   --  Offset every edge of R inwards by its own distance D (I) and
   --  intersect neighbouring offset lines.
   procedure Inset_Ring
     (R : Ring; D : Dist_Array; Result : out Ring; Ok : out Boolean)
   is
      N : constant Natural := Natural (R.Length);
   begin
      Result.Clear;
      Ok := True;
      for I in 0 .. N - 1 loop
         declare
            Prev  : constant P2 := R ((I + N - 1) mod N);
            Cur   : constant P2 := R (I);
            Next  : constant P2 := R ((I + 1) mod N);
            N1    : constant P2 := Edge_Out (Prev, Cur);
            N2    : constant P2 := Edge_Out (Cur, Next);
            D1    : constant Long_Float := D ((I + N - 1) mod N);
            D2    : constant Long_Float := D (I);
            Det   : constant Long_Float := N1.X * N2.Z - N1.Z * N2.X;
            Q     : P2;
         begin
            if abs Det < 0.08 then
               --  (nearly) collinear edges
               if N1.X * N2.X + N1.Z * N2.Z < 0.0 then
                  Ok := False;
                  return;
               end if;
               Q := (-0.5 * (D1 + D2)) * N1;
            else
               Q := ((-D1 * N2.Z + N1.Z * D2) / Det,
                     (-N1.X * D2 + D1 * N2.X) / Det);
            end if;
            if Sqrt (Q.X * Q.X + Q.Z * Q.Z)
              > 2.5 * Long_Float'Max (D1, D2) + 1.0E-6
            then
               Ok := False;
               return;
            end if;
            Result.Append (Cur + Q);
         end;
      end loop;

      --  Every inset edge must keep its direction, otherwise the offset
      --  folded over (narrow wings, short edges).
      for I in 0 .. N - 1 loop
         declare
            J  : constant Natural := (I + 1) mod N;
            Ox : constant Long_Float := R (J).X - R (I).X;
            Oz : constant Long_Float := R (J).Z - R (I).Z;
            Ix : constant Long_Float := Result (J).X - Result (I).X;
            Iz : constant Long_Float := Result (J).Z - Result (I).Z;
         begin
            if Ox * Ix + Oz * Iz <= 0.0 then
               Ok := False;
               return;
            end if;
         end;
      end loop;
   end Inset_Ring;

   procedure Flat_Roof (T : in out Tile_Builder; Outer : Ring;
                        Holes : Ring_Vectors.Vector; Y, Mat, Seed : Long_Float)
   is
      Roof : Poly;
   begin
      Roof.Outer := Outer;
      Roof.Holes := Holes;
      declare
         Pts  : Earcut.Point_Array (0 .. Point_Count (Roof) - 1);
         Tris : Earcut.Index_Vectors.Vector;
         Base : Interfaces.Unsigned_32;
      begin
         Triangulate (Roof, Pts, Tris);
         Base := Interfaces.Unsigned_32 (Natural (T.Verts.Length) / Floats_Per_Vertex);
         for P of Pts loop
            declare
               Dummy : constant Interfaces.Unsigned_32 :=
                 Add_Vertex (T, (P.X, Y, P.Y), (0.0, 1.0, 0.0), P.X, P.Y, Mat, Seed);
            begin
               null;
            end;
         end loop;
         for K in 0 .. Natural (Tris.Length) / 3 - 1 loop
            Tri (T, Solid,
                 Base + Interfaces.Unsigned_32 (Tris.Element (3 * K)),
                 Base + Interfaces.Unsigned_32 (Tris.Element (3 * K + 1)),
                 Base + Interfaces.Unsigned_32 (Tris.Element (3 * K + 2)));
         end loop;
      end;
   end Flat_Roof;

   procedure Solid_Tri (T : in out Tile_Builder; A, B, C : V3; Mat, Seed : Long_Float;
                        U0, U1, V0, V1 : Long_Float := 0.0)
   is
      N  : V3 := Normalize (Cross (B - A, C - A));
      IA, IB, IC : Interfaces.Unsigned_32;
   begin
      if N.Y < 0.0 then
         N := (-1.0) * N;
      end if;
      IA := Add_Vertex (T, A, N, U0, V0, Mat, Seed);
      IB := Add_Vertex (T, B, N, U1, V0, Mat, Seed);
      IC := Add_Vertex (T, C, N, 0.5 * (U0 + U1), V1, Mat, Seed);
      Tri (T, Solid, IA, IB, IC);
   end Solid_Tri;

   --  Planar quad whose normal should point up/outwards
   procedure Roof_Quad (T : in out Tile_Builder; A, B, C, D : V3; Mat, Seed : Long_Float) is
      N : V3 := Normalize (Cross (B - A, D - A));
   begin
      if N.Y < 0.0 then
         N := (-1.0) * N;
      end if;
      Solid_Quad (T, A, B, C, D, N, A.X, B.X, A.Z, C.Z, Mat, Seed);
   end Roof_Quad;

   --  Dome over a (roughly round) outline: rings shrinking towards the centre
   procedure Dome_Roof (T : in out Tile_Builder; R : Ring; Y0, Rh : Long_Float;
                        Mat, Seed : Long_Float)
   is
      Steps : constant := 8;
      N     : constant Natural := Natural (R.Length);
      C     : constant P2 := Centroid (R);
      Base  : constant Interfaces.Unsigned_32 :=
        Interfaces.Unsigned_32 (Natural (T.Verts.Length) / Floats_Per_Vertex);
      Perim : Long_Float := 0.0;
      U     : Long_Float;
   begin
      for I in 0 .. N - 1 loop
         Perim := Perim + Dist (R (I), R ((I + 1) mod N));
      end loop;
      for K in 0 .. Steps loop
         declare
            Th : constant Long_Float := Long_Float (K) / Long_Float (Steps) * Ada.Numerics.Pi / 2.0;
         begin
            U := 0.0;
            for I in 0 .. N loop
               declare
                  P   : constant P2 := R (I mod N);
                  Rad : constant P2 := P - C;
                  RL  : constant Long_Float := Long_Float'Max (Sqrt (Rad.X ** 2 + Rad.Z ** 2), 0.1);
                  Q   : constant P2 := C + Cos (Th) * Rad;
                  Nrm : constant V3 := Normalize
                    ((Rh * Cos (Th) * Rad.X / RL, RL * Sin (Th), Rh * Cos (Th) * Rad.Z / RL));
                  Dummy : Interfaces.Unsigned_32;
               begin
                  if I > 0 then
                     U := U + Dist (R (I - 1), P);
                  end if;
                  Dummy := Add_Vertex (T, (Q.X, Y0 + Rh * Sin (Th), Q.Z), Nrm,
                                       U / Long_Float'Max (Perim, 1.0) * 32.0,
                                       Long_Float (K) / Long_Float (Steps), Mat, Seed);
               end;
            end loop;
         end;
      end loop;
      for K in 0 .. Steps - 1 loop
         for I in 0 .. N - 1 loop
            declare
               use Interfaces;
               A : constant Unsigned_32 := Base + Unsigned_32 (K * (N + 1) + I);
               B : constant Unsigned_32 := A + 1;
               D : constant Unsigned_32 := A + Unsigned_32 (N + 1);
               E : constant Unsigned_32 := D + 1;
            begin
               Tri (T, Solid, A, B, E);
               Tri (T, Solid, A, E, D);
            end;
         end loop;
      end loop;
   end Dome_Roof;

   procedure Pyramid_Roof (T : in out Tile_Builder; R : Ring; Y0, Rh : Long_Float;
                           Mat, Seed : Long_Float)
   is
      N    : constant Natural := Natural (R.Length);
      C    : constant P2 := Centroid (R);
      Apex : constant V3 := (C.X, Y0 + Rh, C.Z);
   begin
      for I in 0 .. N - 1 loop
         declare
            A : constant P2 := R (I);
            B : constant P2 := R ((I + 1) mod N);
         begin
            Solid_Tri (T, (A.X, Y0, A.Z), (B.X, Y0, B.Z), Apex, Mat, Seed);
         end;
      end loop;
   end Pyramid_Roof;

   --  Gabled or hipped roof over a four-cornered outline
   procedure Ridge_Roof (T : in out Tile_Builder; R : Ring; Y0, Rh : Long_Float;
                         Hipped : Boolean; Seed : Long_Float)
   is
      --  Rotate the corners so that edge 0-1 is a long side
      Long_First : constant Boolean :=
        Dist (R (0), R (1)) + Dist (R (2), R (3))
          >= Dist (R (1), R (2)) + Dist (R (3), R (0));
      O  : constant Natural := (if Long_First then 0 else 1);
      A  : constant P2 := R (O);
      B  : constant P2 := R ((O + 1) mod 4);
      C  : constant P2 := R ((O + 2) mod 4);
      D  : constant P2 := R ((O + 3) mod 4);
      M1 : P2 := 0.5 * (D + A);    --  ridge ends over the short sides
      M2 : P2 := 0.5 * (B + C);
      Y1 : constant Long_Float := Y0 + Rh;
   begin
      if Hipped then
         declare
            Half : constant Long_Float := 0.5 * Dist (A, D);
            L    : constant Long_Float := Dist (M1, M2);
            F    : constant Long_Float := Long_Float'Min (0.45, Half / Long_Float'Max (L, 0.01));
            M1n  : constant P2 := M1 + F * (M2 - M1);
            M2n  : constant P2 := M2 + F * (M1 - M2);
         begin
            M1 := M1n;
            M2 := M2n;
         end;
         Solid_Tri (T, (D.X, Y0, D.Z), (A.X, Y0, A.Z), (M1.X, Y1, M1.Z), Mat_Roof, Seed);
         Solid_Tri (T, (B.X, Y0, B.Z), (C.X, Y0, C.Z), (M2.X, Y1, M2.Z), Mat_Roof, Seed);
      else
         --  Vertical gable ends in plain wall
         for Pair in 0 .. 1 loop
            declare
               P  : constant P2 := (if Pair = 0 then D else B);
               Q  : constant P2 := (if Pair = 0 then A else C);
               M  : constant P2 := (if Pair = 0 then M1 else M2);
               No : constant P2 := Edge_Out (P, Q);
               Nr : constant V3 := (No.X, 0.0, No.Z);
               I0 : constant Interfaces.Unsigned_32 :=
                 Add_Vertex (T, (P.X, Y0, P.Z), Nr, -1.0, 4.0, Mat_Wall, Seed);
               I1 : constant Interfaces.Unsigned_32 :=
                 Add_Vertex (T, (Q.X, Y0, Q.Z), Nr, -1.0, 4.0, Mat_Wall, Seed);
               I2 : constant Interfaces.Unsigned_32 :=
                 Add_Vertex (T, (M.X, Y1, M.Z), Nr, -1.0, 5.0, Mat_Wall, Seed);
            begin
               Tri (T, Solid, I0, I1, I2);
            end;
         end loop;
      end if;
      Roof_Quad (T, (A.X, Y0, A.Z), (B.X, Y0, B.Z), (M2.X, Y1, M2.Z), (M1.X, Y1, M1.Z),
                 Mat_Roof, Seed);
      Roof_Quad (T, (C.X, Y0, C.Z), (D.X, Y0, D.Z), (M1.X, Y1, M1.Z), (M2.X, Y1, M2.Z),
                 Mat_Roof, Seed);
   end Ridge_Roof;

   --  Chimney stacks straddle the party walls of Parisian buildings
   procedure Chimney (T : in out Tile_Builder; A, C : P2; Inward : P2;
                      Y, Salt : Long_Float; Id : Osm_Id; K : Natural)
   is
      L     : constant Long_Float := Dist (A, C);
      Dir   : constant P2 := (1.0 / L) * (C - A);
      H1    : constant Long_Float := Hash01 (Id, 100 + K);
      H2    : constant Long_Float := Hash01 (Id, 200 + K);
      Len   : constant Long_Float := Long_Float'Min (0.5 * L, 0.9 + 1.8 * H1);
      Mid   : constant Long_Float := L * (0.25 + 0.5 * Salt);
      S0    : constant Long_Float := Long_Float'Max (0.3, Mid - Len / 2.0);
      S1    : constant Long_Float := Long_Float'Min (L - 0.3, S0 + Len);
      P0    : constant P2 := A + S0 * Dir;
      P1    : constant P2 := A + S1 * Dir;
      Top   : constant Long_Float := Y + 0.7 + 0.7 * H2;
      --  fully on the owner's side, so it never hangs over a lower neighbour
      Stack : constant Quad_P2 := Strip (P0, P1, Inward, 0.02, 0.66);
      Pots  : constant Quad_P2 := Strip (P0 + 0.12 * Dir, P1 - 0.12 * Dir, Inward, 0.2, 0.30);
      Seed  : constant Long_Float := Hash01 (Id, 300 + K);
   begin
      if S1 - S0 < 0.6 then
         return;
      end if;
      --  the stack rises out of the wall below, so it never floats over a
      --  lower roof next to it
      Prism (T, Stack, Y - 3.0, Top, Mat_Chimney, Seed);
      Prism (T, Pots, Top, Top + 0.42, Mat_Pots, Seed);
   end Chimney;

   --  OSM colour value ("#rrggbb", "#rgb" or a common name) packed for
   --  Current_Roof_Colour; 0 when unknown
   function Parse_Colour (S : String) return Long_Float is
      function Hex (C : Character) return Natural is
        (case C is
            when '0' .. '9' => Character'Pos (C) - Character'Pos ('0'),
            when 'a' .. 'f' => Character'Pos (C) - Character'Pos ('a') + 10,
            when 'A' .. 'F' => Character'Pos (C) - Character'Pos ('A') + 10,
            when others => 0);
      R, G, B : Natural;   --  0 .. 255
   begin
      if S'Length = 7 and then S (S'First) = '#' then
         R := Hex (S (S'First + 1)) * 16 + Hex (S (S'First + 2));
         G := Hex (S (S'First + 3)) * 16 + Hex (S (S'First + 4));
         B := Hex (S (S'First + 5)) * 16 + Hex (S (S'First + 6));
      elsif S'Length = 4 and then S (S'First) = '#' then
         R := Hex (S (S'First + 1)) * 17;
         G := Hex (S (S'First + 2)) * 17;
         B := Hex (S (S'First + 3)) * 17;
      elsif One_Of (S, "grey|gray|silver") then
         R := 150; G := 152; B := 156;
      elsif One_Of (S, "darkgrey|darkgray|dimgray|dimgrey") then
         R := 90; G := 92; B := 96;
      elsif S = "black" then
         R := 40; G := 40; B := 42;
      elsif S = "white" then
         R := 225; G := 225; B := 220;
      elsif One_Of (S, "red|darkred|maroon") then
         R := 150; G := 60; B := 45;
      elsif One_Of (S, "brown|sienna") then
         R := 120; G := 80; B := 55;
      elsif One_Of (S, "green|darkgreen") then
         R := 70; G := 110; B := 85;
      elsif One_Of (S, "blue|darkblue|navy") then
         R := 70; G := 85; B := 120;
      elsif One_Of (S, "gold|yellow") then
         R := 200; G := 165; B := 70;
      elsif One_Of (S, "beige|cream|wheat") then
         R := 222; G := 208; B := 178;
      elsif S = "tan" then
         R := 210; G := 180; B := 140;
      elsif One_Of (S, "lightyellow|ivory") then
         R := 240; G := 230; B := 190;
      elsif One_Of (S, "orange") then
         R := 210; G := 120; B := 60;
      elsif One_Of (S, "pink") then
         R := 225; G := 170; B := 170;
      else
         return 0.0;
      end if;
      return 1.0 + Long_Float ((R / 8) * 1024 + (G / 8) * 32 + B / 8);
   end Parse_Colour;

   --  Compass direction tag ("225", "SW") as a unit vector in the ground
   --  plane, or (0, 0) when absent
   function Compass (S : String) return P2 is
      Deg : Long_Float := Num_Value (S);
   begin
      if Deg < 0.0 then
         Deg :=
           (if S = "N" then 0.0 elsif S = "NNE" then 22.5 elsif S = "NE" then 45.0
            elsif S = "ENE" then 67.5 elsif S = "E" then 90.0 elsif S = "ESE" then 112.5
            elsif S = "SE" then 135.0 elsif S = "SSE" then 157.5 elsif S = "S" then 180.0
            elsif S = "SSW" then 202.5 elsif S = "SW" then 225.0 elsif S = "WSW" then 247.5
            elsif S = "W" then 270.0 elsif S = "WNW" then 292.5 elsif S = "NW" then 315.0
            elsif S = "NNW" then 337.5 else -1.0);
      end if;
      if Deg < 0.0 then
         return (0.0, 0.0);
      end if;
      Deg := Deg * Ada.Numerics.Pi / 180.0;
      return (Sin (Deg), -Cos (Deg));
   end Compass;

   --  The part of a ring on the positive (Sign > 0) or negative side of the
   --  line through C perpendicular to V (Sutherland-Hodgman)
   function Clip_Half (R : Ring; C, V : P2; Sign : Long_Float) return Ring is
      Result : Ring;
      N      : constant Natural := Natural (R.Length);
      function S (P : P2) return Long_Float is
        (Sign * ((P.X - C.X) * V.X + (P.Z - C.Z) * V.Z));
   begin
      for I in 0 .. N - 1 loop
         declare
            A  : constant P2 := R (I);
            B  : constant P2 := R ((I + 1) mod N);
            SA : constant Long_Float := S (A);
            SB : constant Long_Float := S (B);
         begin
            if SA >= 0.0 then
               Result.Append (A);
            end if;
            if (SA >= 0.0) /= (SB >= 0.0) then
               Result.Append (A + (SA / (SA - SB)) * (B - A));
            end if;
         end;
      end loop;
      return Result;
   end Clip_Half;

   --  A building whose roof is one plane (skillion) or two planes meeting
   --  at a ridge (gabled over any outline); the walls rise to the roof.
   procedure Planar_Building
     (T : in out Tile_Builder; Shape : Poly; Gable : Boolean; Dir : P2;
      Min_H, Wall_Top, Roof_Part, Floors, Seed : Long_Float)
   is
      Ctr  : constant P2 := Centroid (Shape.Outer);
      Lo, Hi : Long_Float := Long_Float'Last;
      Span : Long_Float;
   begin
      Hi := Long_Float'First;
      for P of Shape.Outer loop
         declare
            D : constant Long_Float := (P.X - Ctr.X) * Dir.X + (P.Z - Ctr.Z) * Dir.Z;
         begin
            Lo := Long_Float'Min (Lo, (if Gable then -abs D else D));
            Hi := Long_Float'Max (Hi, (if Gable then abs D else D));
         end;
      end loop;
      Span := (if Gable then Hi else Hi - Lo);
      if Span < 0.1 then
         Span := 0.1;
      end if;

      declare
         function Height (P : P2) return Long_Float is
            D : constant Long_Float := (P.X - Ctr.X) * Dir.X + (P.Z - Ctr.Z) * Dir.Z;
         begin
            if Gable then
               return Wall_Top + Roof_Part * (1.0 - abs D / Span);
            else
               return Wall_Top + Roof_Part * (Hi - D) / Span;
            end if;
         end Height;

         function V_Of (Y : Long_Float) return Long_Float is
           (Floors * (Y - Min_H) / Long_Float'Max (Wall_Top - Min_H, 0.1));

         procedure Wall_Piece (P, Q : P2; U0, U1 : Long_Float; Nrm : V3) is
            HP : constant Long_Float := Height (P);
            HQ : constant Long_Float := Height (Q);
            I0 : constant Interfaces.Unsigned_32 :=
              Add_Vertex (T, (P.X, Min_H, P.Z), Nrm, U0, 0.0, Mat_Wall, Seed);
            I1 : constant Interfaces.Unsigned_32 :=
              Add_Vertex (T, (Q.X, Min_H, Q.Z), Nrm, U1, 0.0, Mat_Wall, Seed);
            I2 : constant Interfaces.Unsigned_32 :=
              Add_Vertex (T, (Q.X, HQ, Q.Z), Nrm, U1, V_Of (HQ), Mat_Wall, Seed);
            I3 : constant Interfaces.Unsigned_32 :=
              Add_Vertex (T, (P.X, HP, P.Z), Nrm, U0, V_Of (HP), Mat_Wall, Seed);
         begin
            Tri (T, Solid, I0, I1, I2);
            Tri (T, Solid, I0, I2, I3);
         end Wall_Piece;

         procedure Walls (R : Ring) is
            N : constant Natural := Natural (R.Length);
         begin
            for I in 0 .. N - 1 loop
               declare
                  A    : constant P2 := R (I);
                  C    : constant P2 := R ((I + 1) mod N);
                  Len  : constant Long_Float := Dist (A, C);
                  Nrm  : constant V3 := Normalize ((C.Z - A.Z, 0.0, -(C.X - A.X)));
                  Wins : constant Long_Float :=
                    (if Len < 1.8 then -1.0
                     else Long_Float'Max (1.0, Long_Float'Rounding (Len / 3.3)));
                  U0   : constant Long_Float := (if Wins < 0.0 then -1.0 else 0.0);
                  SA   : constant Long_Float := (A.X - Ctr.X) * Dir.X + (A.Z - Ctr.Z) * Dir.Z;
                  SC   : constant Long_Float := (C.X - Ctr.X) * Dir.X + (C.Z - Ctr.Z) * Dir.Z;
               begin
                  if Len > 0.01 then
                     if Gable and then (SA > 0.0) /= (SC > 0.0) and then abs (SA - SC) > 1.0E-6 then
                        declare
                           F : constant Long_Float := SA / (SA - SC);
                           M : constant P2 := A + F * (C - A);
                        begin
                           Wall_Piece (A, M, U0, (if Wins < 0.0 then -1.0 else Wins * F), Nrm);
                           Wall_Piece (M, C, (if Wins < 0.0 then -1.0 else Wins * F), Wins, Nrm);
                        end;
                     else
                        Wall_Piece (A, C, U0, Wins, Nrm);
                     end if;
                  end if;
               end;
            end loop;
         end Walls;

         procedure Roof_Piece (Pl : Poly; Nrm : V3) is
            Pts  : Earcut.Point_Array (0 .. Point_Count (Pl) - 1);
            Tris : Earcut.Index_Vectors.Vector;
            Base : Interfaces.Unsigned_32;
         begin
            if Pl.Outer.Length < 3 then
               return;
            end if;
            Triangulate (Pl, Pts, Tris);
            Base := Interfaces.Unsigned_32 (Natural (T.Verts.Length) / Floats_Per_Vertex);
            for P of Pts loop
               declare
                  Dummy : constant Interfaces.Unsigned_32 :=
                    Add_Vertex (T, (P.X, Height ((P.X, P.Y)), P.Y), Nrm, P.X, 0.0,
                                Mat_Roof, Seed);
               begin
                  null;
               end;
            end loop;
            for K in 0 .. Natural (Tris.Length) / 3 - 1 loop
               Tri (T, Solid,
                    Base + Interfaces.Unsigned_32 (Tris.Element (3 * K)),
                    Base + Interfaces.Unsigned_32 (Tris.Element (3 * K + 1)),
                    Base + Interfaces.Unsigned_32 (Tris.Element (3 * K + 2)));
            end loop;
         end Roof_Piece;

         G : constant Long_Float := Roof_Part / Span;   --  roof gradient
      begin
         Walls (Shape.Outer);
         for H of Shape.Holes loop
            Walls (H);
         end loop;
         if Gable then
            for Sign of Dist_Array'(1.0, -1.0) loop
               declare
                  Half : Poly;
               begin
                  Half.Outer := Clip_Half (Shape.Outer, Ctr, Dir, Sign);
                  Roof_Piece (Half, Normalize ((Sign * G * Dir.X, 1.0, Sign * G * Dir.Z)));
               end;
            end loop;
         else
            Roof_Piece (Shape, Normalize ((G * Dir.X, 1.0, G * Dir.Z)));
         end if;
      end;
   end Planar_Building;

   ---------------------------------------------------------------------------
   --  Home: an apartment you can visit (data/home/home.txt)
   ---------------------------------------------------------------------------

   Home_Id      : Osm_Id := -1;
   Home_Facade  : P2 := (1.0, 0.0);     --  outward direction of the street facade
   Home_Depth   : Long_Float := 10.0;
   Home_Height  : Long_Float := -1.0;   --  wall height of the building, if given
   Rear_From    : Long_Float := -1.0;   --  depth where a lower rear wing starts
   Rear_Height  : Long_Float := -1.0;   --  height of that rear wing
   Kitchen_Off  : Long_Float := 1.8;    --  kitchen window centre from that end
   Home_North   : Boolean := True;      --  kitchen window at the north end
   Output_Dir   : Ada.Strings.Unbounded.Unbounded_String;

   procedure Read_Home (File_Name : String) is
      F : Ada.Text_IO.File_Type;
   begin
      if not Ada.Directories.Exists (File_Name) then
         return;
      end if;
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, File_Name);
      while not Ada.Text_IO.End_Of_File (F) loop
         declare
            Line  : constant String := Ada.Strings.Fixed.Trim
              (Ada.Text_IO.Get_Line (F), Ada.Strings.Both);
            Space : constant Natural := Ada.Strings.Fixed.Index (Line, " ");
         begin
            if Line'Length > 0 and then Line (Line'First) /= '#' and then Space > 0 then
               declare
                  Key   : constant String := Line (Line'First .. Space - 1);
                  Value : constant String := Ada.Strings.Fixed.Trim
                    (Line (Space + 1 .. Line'Last), Ada.Strings.Both);
               begin
                  if Key = "osm_id" then
                     Home_Id := Osm_Id'Value (Value);
                  elsif Key = "facade" then
                     Home_Facade := Compass (if Value = "east" then "E"
                                             elsif Value = "west" then "W"
                                             elsif Value = "north" then "N" else "S");
                  elsif Key = "depth" then
                     Home_Depth := Long_Float'Value (Value);
                  elsif Key = "height" then
                     Home_Height := Long_Float'Value (Value);
                  elsif Key = "rear_from" then
                     Rear_From := Long_Float'Value (Value);
                  elsif Key = "kitchen_offset" then
                     Kitchen_Off := Long_Float'Value (Value);
                  elsif Key = "rear_height" then
                     Rear_Height := Long_Float'Value (Value);
                  elsif Key = "kitchen" then
                     Home_North := Value = "north";
                  end if;
               end;
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (F);
   end Read_Home;

   function Is_Home_Facade (A, C : P2) return Boolean is
     (Dist (A, C) > 2.0
      and then Edge_Out (A, C).X * Home_Facade.X + Edge_Out (A, C).Z * Home_Facade.Z > 0.85);

   function Faces_Inward (A, C : P2) return Boolean is
     (Dist (A, C) > 1.0
      and then Edge_Out (A, C).X * (-Home_Facade.X) + Edge_Out (A, C).Z * (-Home_Facade.Z) > 0.8);

   --  Depth reference of the home facade: dot (P, Facade) along the street
   function Facade_Line (Outer : Ring) return Long_Float is
      N     : constant Natural := Natural (Outer.Length);
      Sum   : Long_Float := 0.0;
      Count : Natural := 0;
   begin
      for I in 0 .. N - 1 loop
         declare
            A : constant P2 := Outer (I);
            C : constant P2 := Outer ((I + 1) mod N);
         begin
            if Is_Home_Facade (A, C) then
               Sum := Sum + A.X * Home_Facade.X + A.Z * Home_Facade.Z
                 + C.X * Home_Facade.X + C.Z * Home_Facade.Z;
               Count := Count + 2;
            end if;
         end;
      end loop;
      return (if Count = 0 then 0.0 else Sum / Long_Float (Count));
   end Facade_Line;

   --  With rear_from / rear_height in home.txt, the home building is cut in
   --  two: the street block (with the apartment) keeps its height, the
   --  courtyard wing behind it becomes a separate, lower building.
   procedure Split_Home is
   begin
      if Home_Id < 0 or else Rear_From <= 0.0 or else Rear_Height <= 0.0 then
         return;
      end if;
      for I in Buildings.First_Index .. Buildings.Last_Index loop
         if Buildings (I).Id = Home_Id and then not Buildings (I).Is_Part then
            declare
               B      : constant Building := Buildings (I);
               Line_D : constant Long_Float := Facade_Line (B.Shape.Outer);
               Inward : constant P2 := (-Home_Facade.X, -Home_Facade.Z);
               Cut    : constant P2 := (Line_D - Rear_From) * Home_Facade;
               Front, Rear : Building := B;
            begin
               Front.Shape.Outer := Clip_Half (B.Shape.Outer, Cut, Inward, -1.0);
               Rear.Shape.Outer := Clip_Half (B.Shape.Outer, Cut, Inward, 1.0);
               Front.Shape.Holes.Clear;
               Rear.Shape.Holes.Clear;
               for H of B.Shape.Holes loop
                  declare
                     M : constant P2 := Centroid (H);
                  begin
                     if (M.X - Cut.X) * Inward.X + (M.Z - Cut.Z) * Inward.Z > 0.0 then
                        Rear.Shape.Holes.Append (H);
                     else
                        Front.Shape.Holes.Append (H);
                     end if;
                  end;
               end loop;
               if Front.Shape.Outer.Length >= 3 and then Rear.Shape.Outer.Length >= 3 then
                  Front.Center := Centroid (Front.Shape.Outer);
                  Bounds (Front.Shape.Outer, Front.X0, Front.X1, Front.Z0, Front.Z1);
                  Rear.Id := B.Id + 1_000_000_000_000;
                  Rear.Center := Centroid (Rear.Shape.Outer);
                  Bounds (Rear.Shape.Outer, Rear.X0, Rear.X1, Rear.Z0, Rear.Z1);
                  Rear.Tags.Include ("height", Long_Float'Image (Rear_Height));
                  Rear.Tags.Exclude ("building:levels");
                  Buildings.Replace_Element (I, Front);
                  Buildings.Append (Rear);
                  Ada.Text_IO.Put_Line ("  home: rear wing split off, height"
                                        & Integer'Image (Integer (Rear_Height)) & " m");
               end if;
            end;
            exit;
         end if;
      end loop;
   end Split_Home;

   --  The top floor of the home building: real window openings with
   --  balconies on the street side and the apartment behind them.
   --  Y0 .. Y1 is the top floor band of the facade.
   --  Tiles holding skyline landmarks; the game keeps them loaded so
   --  they are seen from anywhere in the city
   Skyline : Ada.Strings.Unbounded.Unbounded_String;

   procedure Add_Skyline (P : P2; Name : String) is
   begin
      Ada.Strings.Unbounded.Append
        (Skyline, Integer'Image (Geo.Tile_Of (P.X)) & " " & Integer'Image (Geo.Tile_Of (P.Z))
         & " " & Name & ASCII.LF);
   end Add_Skyline;

   procedure Emit_Home (T : in out Tile_Builder; Outer : Ring; Holes : Ring_Vectors.Vector;
                        Y0, Y1, Floors, Seed : Long_Float) is
      N       : constant Natural := Natural (Outer.Length);
      Thick   : constant := 0.45;                  --  wall thickness
      Y_Low   : constant Long_Float := Y0 + 0.25;  --  apartment floor
      Y_High  : constant Long_Float := Y0 + 0.86 * (Y1 - Y0);
      Y_Ceil  : constant Long_Float := Y1 - 0.2;
      Inward  : constant P2 := (-Home_Facade.X, -Home_Facade.Z);
      Along   : constant P2 := (-Home_Facade.Z, Home_Facade.X);
      S_Min, S_Max : Long_Float := 0.0;
      Line_D  : Long_Float := 0.0;                 --  facade line: dot (P, Facade)
      Count   : Natural := 0;
      Windows : Ada.Strings.Unbounded.Unbounded_String;   --  centres along the facade
      Kitchen_Info : Ada.Strings.Unbounded.Unbounded_String;

      procedure Plain (A, C : P2; Ya, Yb : Long_Float; Nrm : V3; Mat : Long_Float) is
      begin
         if Dist (A, C) > 0.01 and then Yb > Ya + 0.01 then
            Solid_Quad (T, (A.X, Ya, A.Z), (C.X, Ya, C.Z), (C.X, Yb, C.Z), (A.X, Yb, A.Z),
                        Nrm, (if Mat = Mat_Wall then -1.0 else 0.0),
                        (if Mat = Mat_Wall then -1.0 else Dist (A, C)),
                        (if Mat = Mat_Wall then Floors - 1.0 elsif Mat = Mat_Railing then 0.0 else Ya),
                        (if Mat = Mat_Wall then Floors elsif Mat = Mat_Railing then 0.999 else Yb),
                        Mat, Seed);
         end if;
      end Plain;

      function Frame (S, D : Long_Float) return P2 is
        (S * Along + (Line_D - D) * Home_Facade);
   begin
      --  The facade line and its extent along the street
      for I in 0 .. N - 1 loop
         declare
            A : constant P2 := Outer (I);
            C : constant P2 := Outer ((I + 1) mod N);
         begin
            if Is_Home_Facade (A, C) then
               for P of Quad_P2'(A, C, A, C) loop
                  declare
                     SV : constant Long_Float := P.X * Along.X + P.Z * Along.Z;
                  begin
                     S_Min := (if Count = 0 then SV else Long_Float'Min (S_Min, SV));
                     S_Max := (if Count = 0 then SV else Long_Float'Max (S_Max, SV));
                     Line_D := Line_D + P.X * Home_Facade.X + P.Z * Home_Facade.Z;
                     Count := Count + 1;
                  end;
               end loop;
            end if;
         end;
      end loop;
      if Count = 0 then
         return;
      end if;
      Line_D := Line_D / Long_Float (Count);

      --  Facade band with openings, reveals and balconies
      for I in 0 .. N - 1 loop
         declare
            A    : constant P2 := Outer (I);
            C    : constant P2 := Outer ((I + 1) mod N);
            Len  : constant Long_Float := Dist (A, C);
            Dir  : constant P2 := (1.0 / Long_Float'Max (Len, 0.01)) * (C - A);
            Out_N : constant P2 := Edge_Out (A, C);
            In_N : constant P2 := (-1.0) * Out_N;
            Nrm  : constant V3 := (Out_N.X, 0.0, Out_N.Z);
            Wins : constant Natural := Natural (Long_Float'Max (1.0, Long_Float'Rounding (Len / 3.3)));
            Cell : constant Long_Float := Len / Long_Float (Wins);
            Half : constant Long_Float := 0.18 * Cell;
            Pos  : Long_Float := 0.0;
         begin
            if Is_Home_Facade (A, C) then
               for K in 0 .. Wins - 1 loop
                  declare
                     Mid : constant Long_Float := (Long_Float (K) + 0.5) * Cell;
                     L   : constant P2 := A + (Mid - Half) * Dir;
                     R   : constant P2 := A + (Mid + Half) * Dir;
                  begin
                     --  wall from the previous opening to this one, full height
                     Plain (A + Pos * Dir, L, Y0, Y1, Nrm, Mat_Wall);
                     --  below and above the French window
                     Plain (L, R, Y0, Y_Low, Nrm, Mat_Wall);
                     Plain (L, R, Y_High, Y1, Nrm, Mat_Wall);
                     --  reveals
                     Plain (L, L + Thick * In_N, Y_Low, Y_High, (Dir.X, 0.0, Dir.Z), Mat_Plaster);
                     Plain (R + Thick * In_N, R, Y_Low, Y_High, (-Dir.X, 0.0, -Dir.Z), Mat_Plaster);
                     declare
                        LI : constant P2 := L + Thick * In_N;
                        RI : constant P2 := R + Thick * In_N;
                     begin
                        Solid_Quad (T, (L.X, Y_High, L.Z), (R.X, Y_High, R.Z),
                                    (RI.X, Y_High, RI.Z), (LI.X, Y_High, LI.Z),
                                    (0.0, -1.0, 0.0), 0.0, 1.0, 0.0, 1.0, Mat_Plaster, Seed);
                        Solid_Quad (T, (L.X, Y_Low, L.Z), (R.X, Y_Low, R.Z),
                                    (RI.X, Y_Low, RI.Z), (LI.X, Y_Low, LI.Z),
                                    (0.0, 1.0, 0.0), 0.0, 1.0, 0.0, 1.0, Mat_Plaster, Seed);
                     end;
                     --  balcony: stone slab and wrought-iron railing
                     declare
                        BL : constant P2 := L - 0.35 * Dir;
                        BR : constant P2 := R + 0.35 * Dir;
                        D  : constant Long_Float := 0.7;
                        FL : constant P2 := BL + D * Out_N;
                        FR : constant P2 := BR + D * Out_N;
                     begin
                        Prism (T, Strip (BL, BR, Out_N, 0.0, D), Y_Low - 0.18, Y_Low, Mat_Quay, 0.8);
                        Plain (FL, FR, Y_Low, Y_Low + 1.0, Nrm, Mat_Railing);
                        Plain (BL, FL, Y_Low, Y_Low + 1.0, (-Dir.X, 0.0, -Dir.Z), Mat_Railing);
                        Plain (FR, BR, Y_Low, Y_Low + 1.0, (Dir.X, 0.0, Dir.Z), Mat_Railing);
                     end;
                     Pos := Mid + Half;
                     declare
                        WC : constant P2 := A + Mid * Dir;
                     begin
                        Ada.Strings.Unbounded.Append
                          (Windows, " " & Long_Float'Image (WC.X * Along.X + WC.Z * Along.Z));
                     end;
                  end;
               end loop;
               Plain (A + Pos * Dir, C, Y0, Y1, Nrm, Mat_Wall);
            end if;
         end;
      end loop;

      --  The apartment: one large room for now, waiting for the floor plan.
      --  Its back wall stands against the courtyard (a light well in OSM)
      --  nearest the kitchen end, where the kitchen window opens.
      declare
         function S_Of (P : P2) return Long_Float is (P.X * Along.X + P.Z * Along.Z);
         function D_Of (P : P2) return Long_Float is
           (Line_D - (P.X * Home_Facade.X + P.Z * Home_Facade.Z));
         S0 : constant Long_Float := S_Min + Thick;
         S1 : constant Long_Float := S_Max - Thick;
         D0 : constant Long_Float := Thick;
         North_Is_Max : constant Boolean := Along.Z < 0.0;
         Kitchen_S : constant Long_Float :=
           (if Home_North = North_Is_Max then S1 - Kitchen_Off else S0 + Kitchen_Off);
         --  the courtyard wall the kitchen looks through
         Well_Found : Boolean := False;
         WA, WB     : P2 := (0.0, 0.0);
         Best       : Long_Float := Long_Float'Last;
         --  walls the apartment can look out of at the back: every wall of
         --  a light well, and the outer back wall (over a lower rear wing);
         --  stored as point pairs
         Back : Ring;
      begin
         for H of Holes loop
            for I in 0 .. Natural (H.Length) - 1 loop
               Back.Append (H (I));
               Back.Append (H ((I + 1) mod Natural (H.Length)));
            end loop;
         end loop;
         for I in 0 .. N - 1 loop
            if Faces_Inward (Outer (I), Outer ((I + 1) mod N)) then
               Back.Append (Outer (I));
               Back.Append (Outer ((I + 1) mod N));
            end if;
         end loop;
         for E in 0 .. Natural (Back.Length) / 2 - 1 loop
               declare
                  A : constant P2 := Back (2 * E);
                  C : constant P2 := Back (2 * E + 1);
                  O : constant P2 := Edge_Out (A, C);
                  M : constant P2 := 0.5 * (A + C);
                  Score : constant Long_Float := abs (S_Of (M) - Kitchen_S) + D_Of (M);
               begin
                  if Dist (A, C) >= 1.5 and then O.X * Inward.X + O.Z * Inward.Z > 0.8
                    and then D_Of (M) > 4.0 and then D_Of (M) < 16.0 and then Score < Best
                  then
                     Best := Score;
                     Well_Found := True;
                     WA := A;
                     WB := C;
                  end if;
               end;
         end loop;

         declare
            D_Back : constant Long_Float :=
              (if Well_Found then 0.5 * (D_Of (WA) + D_Of (WB)) else Home_Depth);
            D1  : constant Long_Float := D_Back - 0.3;   --  inside of the back wall
            P00 : constant P2 := Frame (S0, D0);
            P10 : constant P2 := Frame (S1, D0);
            P11 : constant P2 := Frame (S1, D1);
            P01 : constant P2 := Frame (S0, D1);
            Up  : constant V3 := (0.0, 1.0, 0.0);
            --  kitchen window centre: on the well wall, as near the kitchen end as fits
            K_Lo : constant Long_Float :=
              (if Well_Found then Long_Float'Min (S_Of (WA), S_Of (WB)) + 0.7 else Kitchen_S);
            K_Hi : constant Long_Float :=
              (if Well_Found then Long_Float'Max (S_Of (WA), S_Of (WB)) - 0.7 else Kitchen_S);
            K_S  : constant Long_Float := Long_Float'Max (K_Lo, Long_Float'Min (K_Hi, Kitchen_S));
            K_W  : constant Long_Float :=
              (if Well_Found then Long_Float'Min (0.6, 0.5 * (K_Hi - K_Lo) + 0.4) else 0.6);
            KA : constant P2 := Frame (K_S - K_W, D1);
            KB : constant P2 := Frame (K_S + K_W, D1);
            OA : constant P2 := Frame (K_S - K_W, D_Back);
            OB : constant P2 := Frame (K_S + K_W, D_Back);
            Back_N : constant V3 := (Home_Facade.X, 0.0, Home_Facade.Z);
            Sill : constant Long_Float := Y_Low + 0.95;
            Head : constant Long_Float := Y_Low + 2.25;
         begin
            --  floor and ceiling
            Solid_Quad (T, (P00.X, Y_Low, P00.Z), (P10.X, Y_Low, P10.Z), (P11.X, Y_Low, P11.Z),
                        (P01.X, Y_Low, P01.Z), Up, S0, S1, D0, D1, Mat_Parquet, Seed);
            Solid_Quad (T, (P00.X, Y_Ceil, P00.Z), (P10.X, Y_Ceil, P10.Z), (P11.X, Y_Ceil, P11.Z),
                        (P01.X, Y_Ceil, P01.Z), (0.0, -1.0, 0.0), S0, S1, D0, D1, Mat_Plaster, Seed);
            --  end walls
            Plain (P00, P01, Y_Low, Y_Ceil, (Along.X, 0.0, Along.Z), Mat_Plaster);
            Plain (P11, P10, Y_Low, Y_Ceil, (-Along.X, 0.0, -Along.Z), Mat_Plaster);
            --  back wall with the kitchen window
            Plain (P01, KA, Y_Low, Y_Ceil, Back_N, Mat_Plaster);
            Plain (KB, P11, Y_Low, Y_Ceil, Back_N, Mat_Plaster);
            Plain (KA, KB, Y_Low, Sill, Back_N, Mat_Plaster);
            Plain (KA, KB, Head, Y_Ceil, Back_N, Mat_Plaster);
            if Well_Found then
               --  an open window: reveals through the wall to the light well
               Plain (KA, OA, Sill, Head, (Along.X, 0.0, Along.Z), Mat_Plaster);
               Plain (OB, KB, Sill, Head, (-Along.X, 0.0, -Along.Z), Mat_Plaster);
               Solid_Quad (T, (KA.X, Sill, KA.Z), (KB.X, Sill, KB.Z), (OB.X, Sill, OB.Z),
                           (OA.X, Sill, OA.Z), Up, 0.0, 1.0, 0.0, 1.0, Mat_Stone, Seed);
               Solid_Quad (T, (KA.X, Head, KA.Z), (KB.X, Head, KB.Z), (OB.X, Head, OB.Z),
                           (OA.X, Head, OA.Z), (0.0, -1.0, 0.0), 0.0, 1.0, 0.0, 1.0,
                           Mat_Plaster, Seed);
               --  the back walls at the top floor, the kitchen one with the opening
               for E in 0 .. Natural (Back.Length) / 2 - 1 loop
                     declare
                        A : constant P2 := Back (2 * E);
                        C : constant P2 := Back (2 * E + 1);
                        O : constant P2 := Edge_Out (A, C);
                        N : constant V3 := (O.X, 0.0, O.Z);
                     begin
                        if A = WA and then C = WB then
                           declare
                              --  OA/OB ordered like A -> C
                              First : constant P2 := (if Dist (A, OA) < Dist (A, OB) then OA else OB);
                              Last  : constant P2 := (if Dist (A, OA) < Dist (A, OB) then OB else OA);
                           begin
                              Plain (A, First, Y0, Y1, N, Mat_Wall);
                              Plain (Last, C, Y0, Y1, N, Mat_Wall);
                              Plain (First, Last, Y0, Sill, N, Mat_Wall);
                              Plain (First, Last, Head, Y1, N, Mat_Wall);
                           end;
                        else
                           Plain (A, C, Y0, Y1, N, Mat_Wall);
                        end if;
                     end;
               end loop;
            else
               Solid_Quad (T, (KA.X, Sill, KA.Z), (KB.X, Sill, KB.Z),
                           (KB.X, Head, KB.Z), (KA.X, Head, KA.Z),
                           Back_N, 0.0, 1.0, 0.0, 1.0, Mat_Glass_Pane, Seed);
            end if;
            Ada.Text_IO.Put_Line ("  home: courtyard " & (if Well_Found then "found" else "not found")
                                  & ", depth" & Integer'Image (Integer (D_Back * 10.0)) & " dm");

            Kitchen_Info := Ada.Strings.Unbounded.To_Unbounded_String
              ("kitchen " & Long_Float'Image (K_S - S0) & " " & Long_Float'Image (D1));
         --  ceiling lights, lit at night like the street lamps
         for Frac of Dist_Array'(0.25, 0.75) loop
            declare
               L : constant P2 := Frame (S0 + Frac * (S1 - S0), 0.5 * (D0 + D1));
            begin
               T.Lights.Append (Float (L.X));
               T.Lights.Append (Float (Lift_Y (L.X, Y_Ceil - 0.4, L.Z)));
               T.Lights.Append (Float (L.Z));
            end;
         end loop;

         --  Tell the game where the apartment is
         declare
            F : Ada.Text_IO.File_Type;
            O : constant P2 := Frame (S0, 0.0);
            function Img (V : Long_Float) return String is (" " & Long_Float'Image (V));
         begin
            Ada.Text_IO.Create (F, Ada.Text_IO.Out_File,
                                Ada.Strings.Unbounded.To_String (Output_Dir) & "/home.txt");
            Ada.Text_IO.Put_Line (F, "# origin_x origin_z along_x along_z in_x in_z length depth floor_y");
            Ada.Text_IO.Put_Line
              (F, Img (O.X) & Img (O.Z) & Img (Along.X) & Img (Along.Z) & Img (Inward.X)
               & Img (Inward.Z) & Img (S1 - S0) & Img (D1) & Img (Lift_Y (O.X, Y_Low, O.Z)));
            Ada.Text_IO.Put_Line (F, "# window centres along the facade (same origin)");
            Ada.Text_IO.Put_Line (F, "windows" & Ada.Strings.Unbounded.To_String (Windows)
                                     & " origin" & Long_Float'Image (S0));
            Ada.Text_IO.Put_Line (F, Ada.Strings.Unbounded.To_String (Kitchen_Info));
            Ada.Text_IO.Close (F);
            Ada.Text_IO.Put_Line ("  home apartment written");
         end;
         end;
      end;
   end Emit_Home;

   type Roof_Kind is (Flat, Dome, Pyramid, Gabled, Hipped, Skillion, Planar_Gable);

   procedure Emit_Building (Index : Natural) is
      B     : constant Building := Buildings (Index);
      Tags  : Tag_Maps.Map renames B.Tags;
      BT    : constant String :=
        (if B.Is_Part then Tag (Tags, "building:part") else Tag (Tags, "building"));
      Small : constant Boolean := One_Of
        (BT, "kiosk|shed|garage|garages|hut|toilets|cabin|service|carport|roof|"
         & "bunker|container|booth|kiosque|greenhouse");
      Religious : constant Boolean := B.Sacred or else One_Of
        (BT, "church|cathedral|chapel|basilica|temple|mosque|synagogue");
      Boat  : constant Boolean :=
        One_Of (BT, "houseboat|ship|boat") or else In_River (B.Center);
      Shape_Tag : constant String := Tag (Tags, "roof:shape");
      Kind  : Roof_Kind :=
        (if One_Of (Shape_Tag, "dome|onion|half-dome") then Dome
         elsif One_Of (Shape_Tag, "pyramidal|cone|round_pyramidal") then Pyramid
         elsif One_Of (Shape_Tag, "gabled|crosspitched|double_saltbox|apse_gabled|saltbox")
         then Gabled
         elsif One_Of (Shape_Tag, "hipped|side_hipped|half-hipped|quadruple_saltbox|"
                       & "gambrel|round_hipped|round")
         then Hipped
         elsif Shape_Tag = "skillion" then Skillion
         else Flat);
      Across    : constant Boolean := Tag (Tags, "roof:orientation") = "across";
      Slope_Dir : P2 := Compass (Tag (Tags, "roof:direction"));
      Height    : constant Long_Float := Num (Tags, "height");
      Levels    : Long_Float := Num (Tags, "building:levels");
      Roof_Lv   : Long_Float := Num (Tags, "roof:levels");
      Roof_H    : constant Long_Float := Num (Tags, "roof:height");
      Min_Tag   : constant Long_Float := Num (Tags, "min_height");
      Min_Level : constant Long_Float := Num (Tags, "building:min_level");
      Min_H, Wall_Top, H, Roof_Part : Long_Float;
      Floors, Roof_Floors : Long_Float;
      Material : constant String :=
        Tag (Tags, "building:facade:material", Tag (Tags, "building:material"));
      Style : constant Long_Float :=
        (if Boat then Style_Boat elsif Religious then Style_Monument
         elsif One_Of (Material, "glass|metal") then Style_Glass
         elsif Small then Style_Small else Style_Haussmann);
      --  Facade colour from OSM (or the material), 0 = Parisian limestone
      Wall_Colour : constant Long_Float :=
        (if Tag (Tags, "building:facade:colour") /= ""
         then Parse_Colour (Tag (Tags, "building:facade:colour"))
         elsif Tag (Tags, "building:colour") /= ""
         then Parse_Colour (Tag (Tags, "building:colour"))
         elsif Material = "brick" then Parse_Colour ("#9a5a44")
         elsif Material = "concrete" then Parse_Colour ("#b5b2aa")
         elsif Material = "plaster" then Parse_Colour ("#e3dccb")
         else 0.0);
      --  The seed is a flat vertex attribute: style + variation, or for
      --  coloured and glass buildings 100 + style * 40000 + packed colour
      Seed  : constant Long_Float :=
        (if Wall_Colour > 0.0 or else Style = Style_Glass
         then 100.0 + Style * 40000.0 + Wall_Colour
         else Style + 0.999 * Hash01 (B.Id));
      TX    : constant Integer :=
        Integer'Max (TX0, Integer'Min (TX1, Geo.Tile_Of (B.Center.X)));
      TZ    : constant Integer :=
        Integer'Max (TZ0, Integer'Min (TZ1, Geo.Tile_Of (B.Center.Z)));
      T     : Tile_Builder renames Tile (TX, TZ).all;
      N_Out : constant Natural := Natural (B.Shape.Outer.Length);
      Party : Bool_Array (0 .. N_Out - 1) := (others => False);
      Owns  : Bool_Array (0 .. N_Out - 1) := (others => False);
      --  Owns: this building draws the shared chimney stacks of that wall
      Inset_Outer : Ring;
      Inset_Holes : Ring_Vectors.Vector;
      Inset_Ok    : Boolean := True;
      Sloped      : Boolean;            --  inset slope from Wall_Top to H
      Slope_Mat   : Long_Float := Mat_Mansard;
      Inset_D     : Long_Float := Mansard_Inset;
      Collides    : constant Boolean := BT /= "roof" and then not Boat;
      Is_Home     : constant Boolean := B.Id = Home_Id and then not B.Is_Part;
      Cut_Y       : Long_Float := 0.0;   --  home: the top floor starts here
      Eq_Radius   : constant Long_Float := Sqrt (abs Signed_Area (B.Shape.Outer) / Ada.Numerics.Pi);
   begin
      Min_H := (if Min_Tag >= 0.0 then Min_Tag
                elsif Min_Level >= 0.0 then Min_Level * Floor_Height
                else 0.0);

      if Is_Home then
         Roof_Lv := 0.0;   --  the apartment is the very top floor
      end if;
      if Kind = Flat then
         if Roof_Lv < 0.0 then
            Roof_Lv := (if not Small and then not Religious and then Height < 0.0
                          and then (Levels < 0.0 or else Levels >= 3.0)
                          and then (Shape_Tag = "" or else Shape_Tag = "mansard")
                        then 1.0 else 0.0);
         end if;
         Roof_Part := (if Roof_H >= 0.0 then Roof_H else Roof_Lv * Mansard_Height);
      else
         Roof_Part :=
           (if Roof_H >= 0.0 then Roof_H
            elsif Roof_Lv > 0.0 then Roof_Lv * Mansard_Height
            else (case Kind is
                     when Dome    => 0.9 * Eq_Radius,
                     when Pyramid => 1.3 * Eq_Radius,
                     when Skillion => Long_Float'Min (0.4 * Eq_Radius, 3.0),
                     when others  => Long_Float'Min (0.6 * Eq_Radius, 5.0)));
         if Roof_Lv < 0.0 then
            Roof_Lv := 0.0;
         end if;
      end if;

      if Is_Home and then Home_Height > 0.0 then
         H := Home_Height;
         if Levels < 0.0 then
            Levels := 8.0;
         end if;
      elsif Height > 0.0 then
         H := Height;
      elsif Religious and then Levels < 0.0 then
         H := 25.0 + (if Kind = Flat then 0.0 else Roof_Part);
      else
         if Levels < 0.0 then
            Levels := (if Small then 1.0 else 5.0);
         end if;
         H := Min_H + Levels * Floor_Height
           + (if Levels >= 2.0 then 1.0 else 0.0) + Roof_Part;
      end if;

      if BT = "roof" and then Min_Tag < 0.0 and then Min_Level < 0.0 then
         Min_H := Long_Float'Max (0.0, H - 0.5);
      end if;
      if Boat then
         --  Barges and restaurant boats float on the sunken river
         Min_H := Water_Level - 0.4;
         H := Water_Level + 2.7 + 0.8 * Hash01 (B.Id, 7);
         Kind := Flat;
         Roof_Part := 0.0;
         Levels := 1.0;
      end if;

      Wall_Top := H - Roof_Part;
      if Kind = Flat then
         if Wall_Top < Min_H + 2.0 then
            Wall_Top := H;
            Roof_Part := 0.0;
         end if;
      elsif Wall_Top < Min_H then
         Wall_Top := Min_H;
         Roof_Part := H - Min_H;
      end if;
      if H <= Min_H + 0.05 then
         return;
      end if;
      if Kind /= Flat and then Roof_Part < 0.3 then
         Kind := Flat;
         Wall_Top := H;
         Roof_Part := 0.0;
      end if;
      --  Gables over other outlines (or turned across) use two planes;
      --  hipped roofs need a simple four-cornered outline, otherwise they
      --  get a hipped-looking inset slope.
      if Kind = Gabled and then (N_Out /= 4 or else Across)
        and then B.Shape.Holes.Is_Empty
      then
         Kind := Planar_Gable;
      end if;
      if Kind in Gabled | Hipped
        and then (N_Out /= 4 or else not B.Shape.Holes.Is_Empty)
      then
         Kind := Flat;
         Slope_Mat := Mat_Roof;
         Inset_D := Long_Float'Min (Roof_Part, 2.5);
      end if;
      Sloped := Kind = Flat and then Roof_Part > 0.0;

      Floors := (if Levels > 0.0 then Levels
                 else Long_Float'Max (1.0, Long_Float'Rounding
                                        ((Wall_Top - Min_H) / 3.2)));
      Roof_Floors := Long_Float'Max (1.0, Long_Float'Rounding (Roof_Lv));
      Cut_Y := Min_H + (Floors - 1.0) * (Wall_Top - Min_H) / Floors;
      Current_Roof_Colour := Parse_Colour (Tag (Tags, "roof:colour"));

      if Collides then
         declare
            procedure Edges_Of (R : Ring) is
            begin
               for I in R.First_Index .. R.Last_Index loop
                  Add_Edge (R (I), R (if I = R.Last_Index then R.First_Index else I + 1),
                            Min_H, H);
               end loop;
            end Edges_Of;
         begin
            Edges_Of (B.Shape.Outer);
            for Hole of B.Shape.Holes loop
               Edges_Of (Hole);
            end loop;
         end;
      end if;
      if B.Edge_Only then
         return;   --  drawn by the neighbouring chunk
      end if;
      if H >= 150.0 then
         Add_Skyline (B.Center, "tower block");
      elsif Religious and then H >= 60.0 then
         Add_Skyline (B.Center, "church");
      end if;

      --  Planar roofs: walls follow the roof, nothing else to add
      if Kind in Skillion | Planar_Gable then
         declare
            Longest : Long_Float := 0.0;
            Along   : P2 := (1.0, 0.0);
         begin
            for I in 0 .. N_Out - 1 loop
               declare
                  A : constant P2 := B.Shape.Outer (I);
                  C : constant P2 := B.Shape.Outer ((I + 1) mod N_Out);
               begin
                  if Dist (A, C) > Longest then
                     Longest := Dist (A, C);
                     Along := (1.0 / Longest) * (C - A);
                     if Kind = Skillion and then Slope_Dir = (0.0, 0.0) then
                        Slope_Dir := Edge_Out (A, C);   --  down towards the long side
                     end if;
                  end if;
               end;
            end loop;
            if Kind = Planar_Gable then
               --  Dir is across the ridge; the ridge runs along the long side
               Slope_Dir := (if Across then Along else (-Along.Z, Along.X));
            elsif Longest > 0.0 and then Tag (Tags, "roof:direction") = "" then
               declare
                  Best : Long_Float := 0.0;
               begin
                  for I in 0 .. N_Out - 1 loop
                     declare
                        A : constant P2 := B.Shape.Outer (I);
                        C : constant P2 := B.Shape.Outer ((I + 1) mod N_Out);
                     begin
                        if Dist (A, C) > Best then
                           Best := Dist (A, C);
                           Slope_Dir := Edge_Out (A, C);
                        end if;
                     end;
                  end loop;
               end;
            end if;
         end;
         Planar_Building (T, B.Shape, Kind = Planar_Gable, Slope_Dir,
                          Min_H, Wall_Top, Roof_Part, Floors, Seed);
         return;
      end if;

      --  Party walls: edges another building is built against
      if not B.Is_Part and then Style = Style_Haussmann then
         for I in 0 .. N_Out - 1 loop
            declare
               A : constant P2 := B.Shape.Outer (I);
               C : constant P2 := B.Shape.Outer ((I + 1) mod N_Out);
            begin
               if Dist (A, C) >= 2.5 then
                  declare
                     Other : constant Integer :=
                       Building_At (0.5 * (A + C) + 0.7 * Edge_Out (A, C), Index);
                  begin
                     Party (I) := Other >= 0;
                     Owns (I) := Other >= 0 and then B.Id < Buildings (Other).Id;
                  end;
               end if;
            end;
         end loop;
      end if;

      --  Mansard: inset the roof outline so the top storey slopes inwards,
      --  except along party walls
      if Sloped then
         declare
            D : Dist_Array (0 .. N_Out - 1);
         begin
            for I in D'Range loop
               D (I) := (if Party (I) then 0.0 else Inset_D);
            end loop;
            Inset_Ring (B.Shape.Outer, D, Inset_Outer, Inset_Ok);
         end;
         for Hole of B.Shape.Holes loop
            exit when not Inset_Ok;
            declare
               R : Ring;
               D : constant Dist_Array (0 .. Natural (Hole.Length) - 1) := (others => Inset_D);
            begin
               Inset_Ring (Hole, D, R, Inset_Ok);
               Inset_Holes.Append (R);
            end;
         end loop;
      end if;
      if not Sloped or else not Inset_Ok then
         Inset_Outer := B.Shape.Outer;
         Inset_Holes := B.Shape.Holes;
      end if;

      --  Walls and mansard faces
      declare
         procedure Do_Ring (R, RI : Ring; Is_Outer : Boolean) is
            N : constant Natural := Natural (R.Length);
         begin
            for I in 0 .. N - 1 loop
               declare
                  J    : constant Natural := (I + 1) mod N;
                  A    : constant P2 := R (I);
                  C    : constant P2 := R (J);
                  Len  : constant Long_Float := Dist (A, C);
                  Nrm  : constant V3 := Normalize ((C.Z - A.Z, 0.0, -(C.X - A.X)));
                  Blind : constant Boolean := Is_Outer and then Party (I);
                  Wins : constant Long_Float :=
                    (if Len < 1.8 then -1.0
                     else Long_Float'Max (1.0, Long_Float'Rounding (Len / 3.3)));
                  U0   : constant Long_Float := (if Wins < 0.0 or else Blind then -1.0 else 0.0);
               begin
                  if Len > 0.01 then
                     if Is_Home and then (not Is_Outer or else Is_Home_Facade (A, C)
                                          or else Faces_Inward (A, C))
                     then
                        --  the top floor is built by Emit_Home
                        Solid_Quad
                          (T, (A.X, Min_H, A.Z), (C.X, Min_H, C.Z),
                           (C.X, Cut_Y, C.Z), (A.X, Cut_Y, A.Z),
                           Nrm, U0, Wins, 0.0, Floors - 1.0, Mat_Wall, Seed);
                     elsif Wall_Top > Min_H then
                        Solid_Quad
                          (T, (A.X, Min_H, A.Z), (C.X, Min_H, C.Z),
                           (C.X, Wall_Top, C.Z), (A.X, Wall_Top, A.Z),
                           Nrm, U0, Wins, 0.0, Floors, Mat_Wall, Seed);
                     end if;
                     if Sloped and then H > Wall_Top then
                        declare
                           P0 : constant V3 := (A.X, Wall_Top, A.Z);
                           P1 : constant V3 := (C.X, Wall_Top, C.Z);
                           P2v : constant V3 := (RI (J).X, H, RI (J).Z);
                           P3 : constant V3 := (RI (I).X, H, RI (I).Z);
                           Sn : V3 := Normalize (Cross (P1 - P0, P3 - P0));
                        begin
                           if Dot (Sn, Nrm) < 0.0 then
                              Sn := (-1.0) * Sn;
                           end if;
                           if Blind then
                              Solid_Quad (T, P0, P1, P2v, P3, Nrm, -1.0, Wins,
                                          Floors, Floors + Roof_Floors, Mat_Wall, Seed);
                           else
                              Solid_Quad (T, P0, P1, P2v, P3, Sn,
                                          (if Slope_Mat = Mat_Mansard then U0 else A.X),
                                          (if Slope_Mat = Mat_Mansard then Wins else C.X),
                                          0.0, Roof_Floors, Slope_Mat, Seed);
                           end if;
                        end;
                     end if;
                  end if;
               end;
            end loop;
         end Do_Ring;
      begin
         Do_Ring (B.Shape.Outer, Inset_Outer, True);
         for K in B.Shape.Holes.First_Index .. B.Shape.Holes.Last_Index loop
            Do_Ring (B.Shape.Holes (K), Inset_Holes (K), False);
         end loop;
      end;

      --  Roof
      case Kind is
         when Dome =>
            Dome_Roof (T, B.Shape.Outer, Wall_Top, Roof_Part, Mat_Dome, Seed);
         when Pyramid =>
            Pyramid_Roof (T, B.Shape.Outer, Wall_Top, Roof_Part,
                          (if Religious or else B.Is_Part then Mat_Dome else Mat_Roof),
                          Seed);
         when Gabled | Hipped =>
            Ridge_Roof (T, B.Shape.Outer, Wall_Top, Roof_Part, Kind = Hipped, Seed);
         when Skillion | Planar_Gable =>
            null;   --  handled above
         when Flat =>
            Flat_Roof (T, Inset_Outer, Inset_Holes, H, Mat_Roof, Seed);
      end case;

      if Is_Home then
         Emit_Home (T, B.Shape.Outer, B.Shape.Holes, Cut_Y, Wall_Top, Floors, Seed);
      end if;

      --  Chimney stacks along the party walls
      if Style = Style_Haussmann and then not B.Is_Part and then Kind = Flat
        and then H - Min_H > 8.0
      then
         for I in 0 .. N_Out - 1 loop
            if Owns (I) then
               declare
                  A : constant P2 := B.Shape.Outer (I);
                  C : constant P2 := B.Shape.Outer ((I + 1) mod N_Out);
                  L : constant Long_Float := Dist (A, C);
                  Inward : constant P2 := (-1.0) * Edge_Out (A, C);
               begin
                  if L >= 3.0 then
                     Chimney (T, A, C, Inward, H, Hash01 (B.Id, 50 + I), B.Id, 2 * I);
                     if L >= 15.0 then
                        Chimney (T, A, C, Inward, H,
                                 Long_Float'Min (1.0, 0.6 + 0.4 * Hash01 (B.Id, 70 + I)),
                                 B.Id, 2 * I + 1);
                     end if;
                  end if;
               end;
            end if;
         end loop;
      end if;
   end Emit_Building;

   ---------------------------------------------------------------------------
   --  Landmarks with their own models
   ---------------------------------------------------------------------------

   --  Smallest rectangle around a ring (by trying all orientations):
   --  centre, unit axes U (long side) and V, half sizes HU >= HV
   procedure Oriented_Box (R : Ring; C : out P2; U, V : out P2; HU, HV : out Long_Float) is
      Best : Long_Float := Long_Float'Last;
   begin
      C := (0.0, 0.0);
      U := (1.0, 0.0);
      V := (0.0, 1.0);
      HU := 0.0;
      HV := 0.0;
      for Step in 0 .. 89 loop
         declare
            A   : constant Long_Float := Long_Float (Step) * Ada.Numerics.Pi / 180.0;
            DU  : constant P2 := (Cos (A), Sin (A));
            DV  : constant P2 := (-Sin (A), Cos (A));
            U0, V0 : Long_Float := Long_Float'Last;
            U1, V1 : Long_Float := Long_Float'First;
         begin
            for P of R loop
               U0 := Long_Float'Min (U0, P.X * DU.X + P.Z * DU.Z);
               U1 := Long_Float'Max (U1, P.X * DU.X + P.Z * DU.Z);
               V0 := Long_Float'Min (V0, P.X * DV.X + P.Z * DV.Z);
               V1 := Long_Float'Max (V1, P.X * DV.X + P.Z * DV.Z);
            end loop;
            if (U1 - U0) * (V1 - V0) < Best then
               Best := (U1 - U0) * (V1 - V0);
               C := (0.5 * (U0 + U1)) * DU + (0.5 * (V0 + V1)) * DV;
               if U1 - U0 >= V1 - V0 then
                  U := DU; V := DV; HU := 0.5 * (U1 - U0); HV := 0.5 * (V1 - V0);
               else
                  U := DV; V := DU; HU := 0.5 * (V1 - V0); HV := 0.5 * (U1 - U0);
               end if;
            end if;
         end;
      end loop;
   end Oriented_Box;

   --  A four-sided frustum: square-ish sections around C0 and C1 with half
   --  sizes along the axes U and V, from Y0 to Y1.  uv are metres along
   --  the face and up, for the lattice and stone patterns.
   procedure Frustum
     (T : in out Tile_Builder; U, V : P2;
      C0 : P2; HU0, HV0, Y0 : Long_Float;
      C1 : P2; HU1, HV1, Y1 : Long_Float;
      Mat, Seed : Long_Float; Caps : Boolean := False)
   is
      type Corner_Array is array (0 .. 3) of P2;
      function Corners (C : P2; HU, HV : Long_Float) return Corner_Array is
        ((C - HU * U - HV * V), (C + HU * U - HV * V),
         (C + HU * U + HV * V), (C - HU * U + HV * V));
      B   : constant Corner_Array := Corners (C0, HU0, HV0);
      Tp  : constant Corner_Array := Corners (C1, HU1, HV1);
      Mid : constant P2 := 0.25 * (B (0) + B (1) + B (2) + B (3));
   begin
      for I in 0 .. 3 loop
         declare
            J  : constant Natural := (I + 1) mod 4;
            P0 : constant V3 := (B (I).X, Y0, B (I).Z);
            P1 : constant V3 := (B (J).X, Y0, B (J).Z);
            P2v : constant V3 := (Tp (J).X, Y1, Tp (J).Z);
            P3 : constant V3 := (Tp (I).X, Y1, Tp (I).Z);
            N  : V3 := Normalize (Cross (P1 - P0, P3 - P0));
            W0 : constant Long_Float := Dist (B (I), B (J));
         begin
            if N.X * (B (I).X - Mid.X) + N.Z * (B (I).Z - Mid.Z) < 0.0 then
               N := (-1.0) * N;
            end if;
            Solid_Quad (T, P0, P1, P2v, P3, N, 0.0, W0, Y0, Y1, Mat, Seed);
         end;
      end loop;
      if Caps then
         Solid_Quad (T, (Tp (0).X, Y1, Tp (0).Z), (Tp (1).X, Y1, Tp (1).Z),
                     (Tp (2).X, Y1, Tp (2).Z), (Tp (3).X, Y1, Tp (3).Z),
                     (0.0, 1.0, 0.0), 0.0, 2.0 * HU1, 0.0, 2.0 * HV1, Mat, Seed);
         Solid_Quad (T, (B (0).X, Y0, B (0).Z), (B (1).X, Y0, B (1).Z),
                     (B (2).X, Y0, B (2).Z), (B (3).X, Y0, B (3).Z),
                     (0.0, -1.0, 0.0), 0.0, 2.0 * HU0, 0.0, 2.0 * HV0, Mat, Seed);
      end if;
   end Frustum;

   --  The Eiffel Tower: four curved legs joining above the second floor
   --  into one tapering shaft, arches between the legs, three platforms.
   --  The half width follows the real profile closely: w(y) = a exp(-y/100).
   procedure Lattice_Tower_Model (T : in out Tile_Builder; B : Building) is
      C : P2;
      U, V : P2;
      HU, HV : Long_Float;
      H : constant Long_Float := Long_Float'Max (100.0, Num (B.Tags, "height"));
      Seed : constant Long_Float := 0.5;
   begin
      Oriented_Box (B.Shape.Outer, C, U, V, HU, HV);
      declare
         A : constant Long_Float := 0.5 * (HU + HV);
         function W (Y : Long_Float) return Long_Float is
           (Long_Float'Max (1.2, A * Exp (-Y / (H / 3.3))));
         --  Leg size (half) grows thinner with height
         function Leg (Y : Long_Float) return Long_Float is
           (Long_Float'Max (2.0, 0.21 * A * Exp (-Y / (H / 2.6))));
         Join : constant Long_Float := 0.35 * H;   --  legs meet (2nd floor)
         Steps : constant := 8;
      begin
         --  Four legs, each a stack of frusta following the curve
         for SU in -1 .. 1 loop
            for SV in -1 .. 1 loop
               if SU /= 0 and then SV /= 0 then
                  for K in 0 .. Steps - 1 loop
                     declare
                        Y0 : constant Long_Float := Join * Long_Float (K) / Long_Float (Steps);
                        Y1 : constant Long_Float := Join * Long_Float (K + 1) / Long_Float (Steps);
                        function Ctr (Y : Long_Float) return P2 is
                          (C + (Long_Float (SU) * (W (Y) - Leg (Y))) * U
                             + (Long_Float (SV) * (W (Y) - Leg (Y))) * V);
                     begin
                        Frustum (T, U, V, Ctr (Y0), Leg (Y0), Leg (Y0), Y0,
                                 Ctr (Y1), Leg (Y1), Leg (Y1), Y1, Mat_Lattice, Seed);
                     end;
                  end loop;
                  --  Collision: the foot of each leg
                  declare
                     F  : constant P2 := C + (Long_Float (SU) * (W (0.0) - Leg (0.0))) * U
                                            + (Long_Float (SV) * (W (0.0) - Leg (0.0))) * V;
                     L  : constant Long_Float := Leg (0.0);
                     Q  : constant Quad_P2 := (F - L * U - L * V, F + L * U - L * V,
                                               F + L * U + L * V, F - L * U + L * V);
                  begin
                     for I in 0 .. 3 loop
                        Add_Edge (Q (I), Q ((I + 1) mod 4), 0.0, Join);
                     end loop;
                  end;
               end if;
            end loop;
         end loop;

         --  Upper shaft
         for K in 0 .. Steps - 1 loop
            declare
               Y0 : constant Long_Float := Join + (0.83 * H - Join) * Long_Float (K) / Long_Float (Steps);
               Y1 : constant Long_Float := Join + (0.83 * H - Join) * Long_Float (K + 1) / Long_Float (Steps);
            begin
               Frustum (T, U, V, C, W (Y0), W (Y0), Y0, C, W (Y1), W (Y1), Y1,
                        Mat_Lattice, Seed);
            end;
         end loop;
         --  Tell the game where the top is (you can go up)
         declare
            F : Ada.Text_IO.File_Type;
            function Img (V : Long_Float) return String is (" " & Long_Float'Image (V));
         begin
            Ada.Text_IO.Create (F, Ada.Text_IO.Out_File,
                                Ada.Strings.Unbounded.To_String (Output_Dir) & "/eiffel.txt");
            Ada.Text_IO.Put_Line
              (F, "# centre_x centre_z u_x u_z top_floor_y deck_half spire_half foot_half");
            Ada.Text_IO.Put_Line
              (F, Img (C.X) & Img (C.Z) & Img (U.X) & Img (U.Z)
               & Img (Lift_Y (C.X, 0.86 * H, C.Z)) & Img (W (0.83 * H) + 1.5)
               & Img (W (0.86 * H)) & Img (W (0.0) - 2.0 * Leg (0.0)));
            Ada.Text_IO.Close (F);
         end;
         --  Top: third floor cabin, lantern and antenna
         Frustum (T, U, V, C, W (0.83 * H) + 1.5, W (0.83 * H) + 1.5, 0.83 * H,
                  C, W (0.83 * H) + 1.5, W (0.83 * H) + 1.5, 0.86 * H, Mat_Stone, 0.3, True);
         Frustum (T, U, V, C, W (0.86 * H), W (0.86 * H), 0.86 * H,
                  C, 1.6, 1.6, 0.9 * H, Mat_Lattice, Seed);
         Frustum (T, U, V, C, 1.6, 1.6, 0.9 * H, C, 0.5, 0.5, H, Mat_Lamp_Post, 0.0);

         --  Platforms: first and second floor, as solid decks with rails
         for Floor in 1 .. 2 loop
            declare
               Y  : constant Long_Float := (if Floor = 1 then 0.175 * H else Join);
               HW : constant Long_Float := W (Y) + 1.0;
            begin
               Frustum (T, U, V, C, HW, HW, Y, C, HW, HW, Y + (if Floor = 1 then 7.0 else 4.0),
                        Mat_Stone, 0.3, True);
            end;
         end loop;

         --  The great arches between the legs, under the first floor
         for Side in 0 .. 3 loop
            declare
               Along : constant P2 := (case Side is when 0 => U, when 1 => V,
                                       when 2 => (-1.0) * U, when others => (-1.0) * V);
               Out_D : constant P2 := (case Side is when 0 => V, when 1 => (-1.0) * U,
                                       when 2 => (-1.0) * V, when others => U);
               Y_Top : constant Long_Float := 0.175 * H;
               Span  : constant Long_Float := W (0.6 * Y_Top) - Leg (0.6 * Y_Top);
               Segs  : constant := 12;
            begin
               for K in 0 .. Segs - 1 loop
                  declare
                     A0 : constant Long_Float := Ada.Numerics.Pi * Long_Float (K) / Long_Float (Segs);
                     A1 : constant Long_Float := Ada.Numerics.Pi * Long_Float (K + 1) / Long_Float (Segs);
                     function Pt (Ang : Long_Float) return P2 is
                       (C + (Span * Cos (Ang)) * Along + (W (Y_Top * 0.7) - 1.0) * Out_D);
                     function Hgt (Ang : Long_Float) return Long_Float is
                       (Y_Top * (0.45 + 0.5 * Sin (Ang)));
                     P0 : constant P2 := Pt (A0);
                     P1 : constant P2 := Pt (A1);
                  begin
                     Solid_Quad (T, (P0.X, Hgt (A0), P0.Z), (P1.X, Hgt (A1), P1.Z),
                                 (P1.X, Hgt (A1) + 2.5, P1.Z), (P0.X, Hgt (A0) + 2.5, P0.Z),
                                 (Out_D.X, 0.0, Out_D.Z), 0.0, 4.0, 0.0, 2.5, Mat_Lattice, Seed);
                  end;
               end loop;
            end;
         end loop;
      end;
   end Lattice_Tower_Model;

   --  A triumphal arch from its footprint and height: four piers, the main
   --  vault across the long sides, smaller arches through the piers and the
   --  attic on top (proportions of the Arc de Triomphe de l'Etoile)
   procedure Triumphal_Arch_Model (T : in out Tile_Builder; B : Building) is
      C : P2;
      U, V : P2;
      HU, HV : Long_Float;
      H : Long_Float := Num (B.Tags, "height");
      Seed : constant Long_Float := 0.6;
   begin
      Oriented_Box (B.Shape.Outer, C, U, V, HU, HV);
      if H <= 0.0 then
         H := 1.1 * HU * 2.0;
      end if;
      declare
         Main_W  : constant Long_Float := 0.32 * HU;     --  half width of the vault
         Main_H  : constant Long_Float := 0.58 * H;      --  vault crown
         Side_W  : constant Long_Float := 0.38 * HV;     --  half width, small arches
         Side_H  : constant Long_Float := 0.37 * H;
         Pier_U0 : constant Long_Float := Main_W;
         Pier_HU : constant Long_Float := 0.5 * (HU - Main_W);
         --  Tell the game where the roof is (you can go up)
         procedure Tell is
            F : Ada.Text_IO.File_Type;
            function Img (X : Long_Float) return String is (" " & Long_Float'Image (X));
         begin
            Ada.Text_IO.Create (F, Ada.Text_IO.Out_File,
                                Ada.Strings.Unbounded.To_String (Output_Dir) & "/arc.txt");
            Ada.Text_IO.Put_Line (F, "# centre_x centre_z u_x u_z roof_y half_u half_v vault_half");
            Ada.Text_IO.Put_Line
              (F, Img (C.X) & Img (C.Z) & Img (U.X) & Img (U.Z) & Img (Lift_Y (C.X, H, C.Z))
               & Img (HU) & Img (HV) & Img (Main_W));
            Ada.Text_IO.Close (F);
         end Tell;
         procedure Block (CU, CV, HBU, HBV, Y0, Y1 : Long_Float) is
            Ctr : constant P2 := C + CU * U + CV * V;
         begin
            Frustum (T, U, V, Ctr, HBU, HBV, Y0, Ctr, HBU, HBV, Y1, Mat_Stone, Seed, True);
         end Block;
      begin
         for SU in -1 .. 1 loop
            if SU /= 0 then
               declare
                  PU : constant Long_Float := Long_Float (SU) * (Pier_U0 + Pier_HU);
                  Sub_HV : constant Long_Float := 0.5 * (HV - Side_W);
               begin
                  --  each pier is split by the small arch into two legs
                  for SV in -1 .. 1 loop
                     if SV /= 0 then
                        Block (PU, Long_Float (SV) * (Side_W + Sub_HV), Pier_HU, Sub_HV,
                               0.0, Main_H);
                        declare
                           Ctr : constant P2 := C + PU * U
                                                + (Long_Float (SV) * (Side_W + Sub_HV)) * V;
                           Q   : constant Quad_P2 :=
                             (Ctr - Pier_HU * U - Sub_HV * V, Ctr + Pier_HU * U - Sub_HV * V,
                              Ctr + Pier_HU * U + Sub_HV * V, Ctr - Pier_HU * U + Sub_HV * V);
                        begin
                           for I in 0 .. 3 loop
                              Add_Edge (Q (I), Q ((I + 1) mod 4), 0.0, H);
                           end loop;
                        end;
                     end if;
                  end loop;
                  --  above the small arch
                  Block (PU, 0.0, Pier_HU, Side_W, Side_H, Main_H);
               end;
            end if;
         end loop;
         if HU > 15.0 then   --  the one at the Étoile (not the Carrousel)
            Tell;
         end if;
         --  attic over everything
         Block (0.0, 0.0, HU, HV, Main_H, H);
         --  the vault: slices following a half circle
         declare
            Slices : constant := 10;
            Spring : constant Long_Float := Main_H - Main_W;
         begin
            for K in 0 .. Slices - 1 loop
               declare
                  X0 : constant Long_Float := -Main_W + 2.0 * Main_W * Long_Float (K) / Long_Float (Slices);
                  X1 : constant Long_Float := X0 + 2.0 * Main_W / Long_Float (Slices);
                  XM : constant Long_Float := 0.5 * (X0 + X1);
                  Y  : constant Long_Float :=
                    Spring + Sqrt (Long_Float'Max (0.0, Main_W * Main_W - XM * XM));
               begin
                  if Y < Main_H - 0.05 then
                     Block (XM, 0.0, 0.5 * (X1 - X0), HV, Y, Main_H);
                  end if;
               end;
            end loop;
         end;
      end;
   end Triumphal_Arch_Model;

   ---------------------------------------------------------------------------
   --  Hand-placed landmarks (data/landmarks.txt)
   ---------------------------------------------------------------------------

   --  The Fontaine Saint-Sulpice: three stacked octagonal basins, a square
   --  pavilion with the four seated bishops between pilasters, a cupola,
   --  and four lions on pedestals in the lower basin.
   procedure Fountain_Saint_Sulpice (C : P2; Rot_Deg, R0 : Long_Float) is
      T    : Tile_Builder renames Tile_At (C).all;
      A    : constant Long_Float := Rot_Deg * Ada.Numerics.Pi / 180.0;
      U    : constant P2 := (Cos (A), Sin (A));          --  faces one side
      V    : constant P2 := (-Sin (A), Cos (A));
      Seed : constant Long_Float := 0.45;

      function Corner (R : Long_Float; K : Natural) return P2 is
        (C + R * P2'(Cos (A + Ada.Numerics.Pi / 8.0 + Long_Float (K) * Ada.Numerics.Pi / 4.0),
                     Sin (A + Ada.Numerics.Pi / 8.0 + Long_Float (K) * Ada.Numerics.Pi / 4.0)));

      --  vertical octagon walls of circumradius R from Y0 to Y1, facing out
      --  (or in)
      procedure Oct_Wall (R, Y0, Y1 : Long_Float; Outward : Boolean) is
      begin
         for K in 0 .. 7 loop
            declare
               P : constant P2 := Corner (R, K);
               Q : constant P2 := Corner (R, K + 1);
               N : P2 := Edge_Out (Q, P);   --  corners run anticlockwise
            begin
               if N.X * (P.X - C.X) + N.Z * (P.Z - C.Z) < 0.0 then
                  N := (-1.0) * N;
               end if;
               if not Outward then
                  N := (-1.0) * N;
               end if;
               Solid_Quad (T, (P.X, Y0, P.Z), (Q.X, Y0, Q.Z), (Q.X, Y1, Q.Z), (P.X, Y1, P.Z),
                           (N.X, 0.0, N.Z), 0.0, Dist (P, Q), Y0, Y1, Mat_Stone, Seed);
            end;
         end loop;
      end Oct_Wall;

      --  flat octagonal ring between R_In and R_Out at height Y (R_In = 0:
      --  a full octagon); Mat_Water for the basins
      procedure Oct_Flat (R_In, R_Out, Y, Mat : Long_Float) is
      begin
         for K in 0 .. 7 loop
            declare
               P0 : constant P2 := Corner (R_Out, K);
               P1 : constant P2 := Corner (R_Out, K + 1);
               Q0 : constant P2 := Corner (R_In, K);
               Q1 : constant P2 := Corner (R_In, K + 1);
            begin
               Solid_Quad (T, (Q0.X, Y, Q0.Z), (P0.X, Y, P0.Z), (P1.X, Y, P1.Z), (Q1.X, Y, Q1.Z),
                           (0.0, 1.0, 0.0), Q0.X, P1.X, Q0.Z, P1.Z, Mat, Seed);
            end;
         end loop;
      end Oct_Flat;

      procedure Basin (R, Y0, Y_Rim, Y_Water : Long_Float) is
      begin
         Oct_Wall (R, Y0, Y_Rim, True);
         Oct_Wall (R - 0.45, Y_Water, Y_Rim, False);
         Oct_Flat (R - 0.45, R, Y_Rim, Mat_Stone);
         Oct_Flat (0.0, R - 0.45, Y_Water, Mat_Water);
      end Basin;

      procedure Block (Ctr : P2; DU, DV : P2; HU, HV, Y0, Y1 : Long_Float) is
      begin
         Frustum (T, DU, DV, Ctr, HU, HV, Y0, Ctr, HU, HV, Y1, Mat_Stone, Seed, True);
      end Block;

      Half : constant Long_Float := 1.7;   --  the pavilion
   begin
      --  Lower, middle and upper basins
      Basin (R0, 0.0, 0.6, 0.35);
      Basin (0.52 * R0, 0.35, 1.9, 1.7);
      Basin (0.33 * R0, 1.7, 3.15, 2.95);
      for K in 0 .. 7 loop
         Add_Edge (Corner (R0, K), Corner (R0, K + 1), 0.0, 12.0);
      end loop;

      --  The pavilion: socle, body with corner pilasters, entablature, attic
      Block (C, U, V, Half + 0.3, Half + 0.3, 2.95, 3.7);
      Block (C, U, V, Half, Half, 3.7, 9.0);
      for SU in -1 .. 1 loop
         for SV in -1 .. 1 loop
            if SU /= 0 and then SV /= 0 then
               Block (C + (Long_Float (SU) * (Half - 0.1)) * U + (Long_Float (SV) * (Half - 0.1)) * V,
                      U, V, 0.3, 0.3, 3.7, 8.9);
            end if;
         end loop;
      end loop;
      Block (C, U, V, Half + 0.3, Half + 0.3, 8.9, 9.6);
      Block (C, U, V, Half - 0.05, Half - 0.05, 9.6, 10.4);
      --  cupola and finial
      declare
         Circle : Ring;
      begin
         for K in 0 .. 15 loop
            declare
               B : constant Long_Float := Long_Float (K) * Ada.Numerics.Pi / 8.0;
            begin
               Circle.Append (C + (Half - 0.15) * P2'(Cos (B), Sin (B)));
            end;
         end loop;
         Dome_Roof (T, Circle, 10.4, 1.4, Mat_Dome, Seed);
      end;
      Frustum (T, U, V, C, 0.22, 0.22, 11.75, C, 0.05, 0.05, 12.6, Mat_Dome, Seed);

      --  The four bishops, seated in front of each face, and the lions
      --  on pedestals in the lower basin, facing out
      for Side in 0 .. 3 loop
         declare
            Rd : constant P2 := (case Side is when 0 => U, when 1 => V,
                                 when 2 => (-1.0) * U, when others => (-1.0) * V);
            Td : constant P2 := (-Rd.Z, Rd.X);
            Face : constant P2 := C + (Half + 0.05) * Rd;
         begin
            --  bishop: pedestal, seated body, shoulders and head
            Block (Face + 0.35 * Rd, Rd, Td, 0.4, 0.55, 4.2, 4.8);
            Block (Face + 0.35 * Rd, Rd, Td, 0.35, 0.45, 4.8, 6.1);
            Block (Face + 0.3 * Rd, Rd, Td, 0.25, 0.32, 6.1, 6.6);
            Block (Face + 0.3 * Rd, Rd, Td, 0.14, 0.13, 6.6, 6.95);
            --  lion couchant on its pedestal, head outwards
            declare
               P : constant P2 := C + (0.66 * R0) * Rd;
            begin
               Block (P, Rd, Td, 1.25, 0.65, 0.35, 1.35);
               Block (P, Rd, Td, 0.95, 0.38, 1.35, 1.95);
               Block (P + 0.85 * Rd, Rd, Td, 0.38, 0.42, 1.55, 2.45);   --  mane
               Block (P + 1.2 * Rd, Rd, Td, 0.18, 0.2, 1.7, 2.15);     --  muzzle
               Add_Edge (P - 1.25 * Rd - 0.65 * Td, P + 1.25 * Rd - 0.65 * Td, 0.0, 2.0);
            end;
         end;
      end loop;

      --  Water falling from the upper basin into the middle one, on the
      --  diagonals
      for K in 0 .. 3 loop
         declare
            B   : constant Long_Float := A + Ada.Numerics.Pi / 4.0 + Long_Float (K) * Ada.Numerics.Pi / 2.0;
            Rd  : constant P2 := (Cos (B), Sin (B));
            Td  : constant P2 := (-Rd.Z, Rd.X);
            Ap  : constant Long_Float := 0.33 * R0 * Cos (Ada.Numerics.Pi / 8.0) + 0.08;
            P   : constant P2 := C + Ap * Rd - 0.7 * Td;
            Q   : constant P2 := C + Ap * Rd + 0.7 * Td;
            P2b : constant P2 := C + (Ap + 0.5) * Rd - 0.8 * Td;
            Q2b : constant P2 := C + (Ap + 0.5) * Rd + 0.8 * Td;
         begin
            Solid_Quad (T, (P2b.X, 1.7, P2b.Z), (Q2b.X, 1.7, Q2b.Z), (Q.X, 3.15, Q.Z), (P.X, 3.15, P.Z),
                        (Rd.X, 0.3, Rd.Z), 0.0, 1.0, 0.0, 1.0, Mat_Water, Seed);
         end;
      end loop;
   end Fountain_Saint_Sulpice;

   type Long_Float_List is array (Positive range <>) of Long_Float;

   --  Places from data/landmarks.txt the other passes need to know about:
   --  pylons (the OSM buildings there are left out) and areas of ornate
   --  street lamps
   type Hand_Spot is record
      Kind : Ada.Strings.Unbounded.Unbounded_String;
      X, Z, Size : Long_Float;
   end record;
   package Spot_Vectors is new Ada.Containers.Vectors (Positive, Hand_Spot);
   Hand_Spots : Spot_Vectors.Vector;

   procedure Read_Hand_Spots (File_Name : String) is
      F : Ada.Text_IO.File_Type;
   begin
      if not Ada.Directories.Exists (File_Name) then
         return;
      end if;
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, File_Name);
      while not Ada.Text_IO.End_Of_File (F) loop
         declare
            use Ada.Strings.Unbounded;
            Line  : constant String := Ada.Text_IO.Get_Line (F) & " ";
            Words : array (1 .. 5) of Unbounded_String;
            N     : Natural := 0;
            Start : Natural := 0;
            X, Z  : Long_Float;
         begin
            if Line (Line'First) /= '#' then
               for I in Line'Range loop
                  if Line (I) = ' ' then
                     if Start > 0 and then N < Words'Last then
                        N := N + 1;
                        Words (N) := To_Unbounded_String (Line (Start .. I - 1));
                     end if;
                     Start := 0;
                  elsif Start = 0 then
                     Start := I;
                  end if;
               end loop;
            end if;
            if N = 5 then
               Geo.To_Local (Long_Float'Value (To_String (Words (2))), Long_Float'Value (To_String (Words (3))),
                             X, Z);
               declare
                  W5 : constant String := To_String (Words (5));
                  SL : constant Natural := Ada.Strings.Fixed.Index (W5, "/");   --  "a/b": a
               begin
                  Hand_Spots.Append
                    ((Words (1), X, Z, Long_Float'Value (if SL > 0 then W5 (W5'First .. SL - 1) else W5)));
               end;
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (F);
   end Read_Hand_Spots;

   function In_Spot (Kind : String; X, Z : Long_Float; Extra : Long_Float := 0.0) return Boolean is
   begin
      for H of Hand_Spots loop
         if Ada.Strings.Unbounded.To_String (H.Kind) = Kind
           and then (H.X - X) ** 2 + (H.Z - Z) ** 2 < (H.Size + Extra) ** 2
         then
            return True;
         end if;
      end loop;
      return False;
   end In_Spot;

   --  A box of any orientation: centre C, unit axes AX, AY, AZ (right
   --  handed) and half sizes along them
   procedure Any_Box (T : in out Tile_Builder; C, AX, AY, AZ : V3; HX, HY, HZ : Long_Float;
                      Mat, Seed : Long_Float) is
      procedure Side (N, A, B : V3; HN, HA, HB : Long_Float) is
         F : constant V3 := C + HN * N;
      begin
         Solid_Quad (T, F - HA * A - HB * B, F + HA * A - HB * B, F + HA * A + HB * B, F - HA * A + HB * B,
                     N, 0.0, 2.0 * HA, 0.0, 2.0 * HB, Mat, Seed);
      end Side;
   begin
      Side (AX, AY, AZ, HX, HY, HZ);
      Side ((-1.0) * AX, AZ, AY, HX, HZ, HY);
      Side (AY, AZ, AX, HY, HZ, HX);
      Side ((-1.0) * AY, AX, AZ, HY, HX, HZ);
      Side (AZ, AX, AY, HZ, HX, HY);
      Side ((-1.0) * AZ, AY, AX, HZ, HY, HX);
   end Any_Box;

   --  The same, with its long axis along D (any direction) and its width
   --  along the horizontal W (normal to D)
   procedure Beam (T : in out Tile_Builder; C, D, W : V3; HD, HW, HT : Long_Float;
                   Mat, Seed : Long_Float) is
      DN : constant V3 := Normalize (D);
      WN : constant V3 := Normalize (W - Dot (W, DN) * DN);
   begin
      Any_Box (T, C, DN, WN, Cross (DN, WN), HD, HW, HT, Mat, Seed);
   end Beam;

   --  A pylon of the Pont Alexandre III: a square stone column on a socle,
   --  a cornice and an attic, crowned by a gilded winged horse held by a
   --  Fame; a seated stone figure at its foot.  Facing: the way the horse
   --  rears (away from the river), in degrees in the X/Z plane.
   procedure Bridge_Pylon (C : P2; Facing_Deg, Half : Long_Float) is
      T    : Tile_Builder renames Tile_At (C).all;
      A    : constant Long_Float := Facing_Deg * Ada.Numerics.Pi / 180.0;
      U    : constant P2 := (Cos (A), Sin (A));
      V    : constant P2 := (-Sin (A), Cos (A));
      F    : constant V3 := (U.X, 0.0, U.Z);
      S    : constant V3 := (V.X, 0.0, V.Z);
      Up   : constant V3 := (0.0, 1.0, 0.0);
      Seed : constant Long_Float := 0.3;
      Top  : constant Long_Float := 17.0;
      function At_C (Along, Side_Off, Y : Long_Float) return V3 is
        ((C.X, Y, C.Z) + Along * F + Side_Off * S);
      procedure Block (Ctr : P2; HU, HV, Y0, Y1 : Long_Float; Mat : Long_Float := Mat_Stone) is
      begin
         Frustum (T, U, V, Ctr, HU, HV, Y0, Ctr, HU, HV, Y1, Mat, Seed, True);
      end Block;
      function Dir (Deg_Up : Long_Float) return V3 is
        (Cos (Deg_Up * Ada.Numerics.Pi / 180.0) * F + Sin (Deg_Up * Ada.Numerics.Pi / 180.0) * Up);
   begin
      --  socle, the shaft with corner pilasters, cornice, attic, top
      Block (C, Half + 0.35, Half + 0.35, 0.0, 2.6);
      Block (C, Half + 0.5, Half + 0.5, 2.6, 3.0);
      Block (C, Half, Half, 3.0, 14.0);
      for SU in -1 .. 1 loop
         for SV in -1 .. 1 loop
            if SU /= 0 and then SV /= 0 then
               Block (C + (Long_Float (SU) * (Half - 0.15)) * U + (Long_Float (SV) * (Half - 0.15)) * V,
                      0.4, 0.4, 3.0, 13.9);
            end if;
         end loop;
      end loop;
      Block (C, Half + 0.25, Half + 0.25, 12.6, 13.0);
      Block (C, Half + 0.55, Half + 0.55, 13.9, 14.8);
      Block (C, Half - 0.25, Half - 0.25, 14.8, 16.3);
      Block (C, Half - 0.05, Half - 0.05, 16.3, Top);
      for K in 0 .. 3 loop   --  the corners of the base, for walking into
         declare
            R : constant Long_Float := Half + 0.35;
            P : constant P2 := C + (if K mod 2 = 0 then R else -R) * U + (if K < 2 then R else -R) * V;
            Q : constant P2 := C + (if K mod 2 = 0 then R else -R) * U + (if K < 2 then -R else R) * V;
         begin
            Add_Edge (P, Q, 0.0, Top);
         end;
      end loop;
      Add_Edge (C + (Half + 0.35) * U + (Half + 0.35) * V, C - (Half + 0.35) * U + (Half + 0.35) * V, 0.0, Top);
      Add_Edge (C + (Half + 0.35) * U - (Half + 0.35) * V, C - (Half + 0.35) * U - (Half + 0.35) * V, 0.0, Top);

      --  the seated figure at its foot, on a pedestal before the face
      Block (C + (Half + 1.1) * U, 0.8, 1.2, 0.0, 1.3);
      Block (C + (Half + 1.0) * U, 0.55, 0.6, 1.3, 2.6);
      Block (C + (Half + 0.95) * U, 0.35, 0.42, 2.6, 3.3);
      Block (C + (Half + 0.95) * U, 0.17, 0.15, 3.3, 3.75);
      Block (C + (Half + 1.55) * U, 0.35, 0.55, 1.3, 1.8);   --  the knees

      --  the gilded group: a plinth, the horse rearing, its wings, the Fame
      Block (C, 1.5, 1.0, Top, Top + 0.5, Mat_Gilt);
      declare
         Body_C : constant V3 := At_C (0.2, 0.0, Top + 2.0);
         Body_D : constant V3 := Dir (35.0);
         Front  : constant V3 := Body_C + 1.05 * Body_D;
         Rear   : constant V3 := Body_C - 1.0 * Body_D;
         Neck_D : constant V3 := Dir (68.0);
         Neck_C : constant V3 := Front + 0.42 * Neck_D + 0.1 * Up;
         Head_D : constant V3 := Dir (-25.0);
         Head_C : constant V3 := Neck_C + 0.5 * Neck_D + 0.25 * Head_D;
      begin
         Beam (T, Body_C, Body_D, S, 1.15, 0.38, 0.42, Mat_Gilt, Seed);
         Beam (T, Neck_C, Neck_D, S, 0.5, 0.2, 0.27, Mat_Gilt, Seed);
         Beam (T, Head_C, Head_D, S, 0.33, 0.15, 0.17, Mat_Gilt, Seed);
         for Side_Off of Long_Float_List'(-0.2, 0.2) loop
            --  hind legs down to the plinth, front legs pawing the air
            declare
               Hip  : constant V3 := Rear + Side_Off * S - 0.2 * Up;
               Foot : constant V3 := At_C (-0.55, Side_Off, Top + 0.5);
               Sh   : constant V3 := Front + Side_Off * S - 0.3 * Up;
               Fore : constant V3 := Dir (-35.0);
            begin
               Beam (T, 0.5 * (Hip + Foot), Hip - Foot, S, 0.5 * Sqrt (Dot (Hip - Foot, Hip - Foot)), 0.09, 0.11,
                     Mat_Gilt, Seed);
               Beam (T, Sh + 0.35 * Fore, Fore, S, 0.38, 0.08, 0.09, Mat_Gilt, Seed);
            end;
            --  a wing, spread up and back
            declare
               Root : constant V3 := Body_C + 0.35 * Body_D + (Side_Off * 1.6) * S + 0.3 * Up;
               WD   : constant V3 := Normalize ((-0.45) * F + 0.85 * Up + (Side_Off * 2.0) * S);
            begin
               Beam (T, Root + 1.0 * WD, WD, Body_D, 1.1, 0.5, 0.05, Mat_Gilt, Seed);
            end;
         end loop;
         Beam (T, Rear - 0.45 * Body_D - 0.3 * Up, Dir (-60.0), S, 0.45, 0.08, 0.08, Mat_Gilt, Seed);   --  tail
         --  the Fame beside it: robe, body, head, an arm up to the bridle
         declare
            P : constant V3 := At_C (-0.2, 1.0, Top + 0.5);
         begin
            Any_Box (T, P + 0.7 * Up, F, Up, Cross (F, Up), 0.28, 0.7, 0.3, Mat_Gilt, Seed);
            Any_Box (T, P + 1.75 * Up, F, Up, Cross (F, Up), 0.2, 0.35, 0.23, Mat_Gilt, Seed);
            Any_Box (T, P + 2.3 * Up, F, Up, Cross (F, Up), 0.12, 0.16, 0.12, Mat_Gilt, Seed);
            Beam (T, P + 2.1 * Up + 0.35 * F - 0.25 * S, Dir (55.0) - 0.4 * S, S, 0.4, 0.06, 0.06, Mat_Gilt, Seed);
         end;
      end;
   end Bridge_Pylon;

   --  A flat panel in a vertical plane: centre (along the facade, out
   --  from it, height), half width and half height, facing F
   procedure Panel (T : in out Tile_Builder; C : P2; F, S : V3; Side_Off, Out_Off, Y0, Y1, HW : Long_Float;
                    Mat, Seed : Long_Float) is
      B : constant V3 := (C.X, 0.0, C.Z) + Out_Off * F + Side_Off * S;
   begin
      Solid_Quad (T, B - HW * S + Y0 * V3'(0.0, 1.0, 0.0), B + HW * S + Y0 * V3'(0.0, 1.0, 0.0),
                  B + HW * S + Y1 * V3'(0.0, 1.0, 0.0), B - HW * S + Y1 * V3'(0.0, 1.0, 0.0),
                  F, 0.0, 2.0 * HW, Y0, Y1, Mat, Seed);
   end Panel;

   --  A gilded statue group for a roof corner: a winged figure standing
   --  between two kneeling ones (the Harmony and Poetry of the Opéra)
   procedure Gilt_Group (T : in out Tile_Builder; C : P2; F, S : V3; Y : Long_Float; Seed : Long_Float) is
      Up : constant V3 := (0.0, 1.0, 0.0);
      B  : constant V3 := (C.X, Y, C.Z);
   begin
      Any_Box (T, B + 0.45 * Up, F, Up, Cross (F, Up), 1.4, 0.45, 2.2, Mat_Gilt, Seed);
      Any_Box (T, B + 2.2 * Up, F, Up, Cross (F, Up), 0.35, 1.3, 0.35, Mat_Gilt, Seed);
      Any_Box (T, B + 3.75 * Up, F, Up, Cross (F, Up), 0.18, 0.25, 0.18, Mat_Gilt, Seed);
      for Side_Off of Long_Float_List'(-1.0, 1.0) loop
         Beam (T, B + 3.2 * Up + (Side_Off * 0.9) * S - 0.3 * F,
               Normalize (0.8 * Up + (Side_Off * 0.6) * S - 0.3 * F), F, 1.0, 0.45, 0.05, Mat_Gilt, Seed);
         Any_Box (T, B + 1.45 * Up + (Side_Off * 1.35) * S + 0.3 * F, F, Up, Cross (F, Up), 0.4, 0.55, 0.35,
                  Mat_Gilt, Seed);
         Any_Box (T, B + 2.2 * Up + (Side_Off * 1.35) * S + 0.3 * F, F, Up, Cross (F, Up), 0.15, 0.2, 0.15,
                  Mat_Gilt, Seed);
      end loop;
      Beam (T, B + 4.4 * Up + 0.2 * F, Normalize (Up + 0.3 * F), S, 0.6, 0.05, 0.05, Mat_Gilt, Seed);   --  a raised arm
   end Gilt_Group;

   --  The front of the Palais Garnier, before the wall of its OSM outline:
   --  the steps, the arcade of seven arches, the loggia with its paired
   --  columns and gilded busts, the entablature, the attic with gilded
   --  masks, and the two gilded groups on the corners of the roof
   procedure Opera_Front (C : P2; Facing_Deg, Half : Long_Float) is
      T    : Tile_Builder renames Tile_At (C).all;
      A    : constant Long_Float := Facing_Deg * Ada.Numerics.Pi / 180.0;
      U    : constant P2 := (Cos (A), Sin (A));
      V    : constant P2 := (-Sin (A), Cos (A));
      F    : constant V3 := (U.X, 0.0, U.Z);
      S    : constant V3 := (V.X, 0.0, V.Z);
      Seed : constant Long_Float := 0.4;
      function At_P (Out_Off, Side_Off : Long_Float) return P2 is (C + Out_Off * U + Side_Off * V);
      procedure Block (Out_Off, Side_Off, HU, HV, Y0, Y1 : Long_Float; Mat : Long_Float := Mat_Stone) is
      begin
         Frustum (T, U, V, At_P (Out_Off, Side_Off), HU, HV, Y0, At_P (Out_Off, Side_Off), HU, HV, Y1, Mat, Seed,
                  True);
      end Block;
      Dark : constant Long_Float := Mat_Glass_Pane;
   begin
      --  steps across the front
      Block (3.2, 0.0, 1.0, Half - 4.0, 0.0, 0.2);
      Block (2.2, 0.0, 1.0, Half - 4.0, 0.0, 0.4);
      Block (1.2, 0.0, 1.0, Half - 4.0, 0.0, 0.6);
      --  the stone face, in three storeys
      Block (0.0, 0.0, 0.3, Half, 0.0, 9.6);
      Block (0.1, 0.0, 0.45, Half + 0.2, 9.6, 10.4);
      Block (0.0, 0.0, 0.3, Half, 10.4, 20.4);
      Block (0.7, 0.0, 1.1, Half + 0.3, 20.4, 22.2);
      Block (0.0, 0.0, 0.3, Half - 0.4, 22.2, 26.6);
      Block (0.2, 0.0, 0.6, Half, 26.6, 27.3);
      Block (0.0, 0.0, 0.3, Half - 0.6, 27.3, 30.6);   --  the upper attic
      Block (0.25, 0.0, 0.65, Half, 30.6, 31.4);
      --  the arcade: seven arches with a stepped head
      for K in -3 .. 3 loop
         declare
            X : constant Long_Float := Long_Float (K) * 6.4;
         begin
            Panel (T, C, F, S, X, 0.32, 0.6, 6.8, 2.1, Dark, Seed);
            Panel (T, C, F, S, X, 0.32, 6.8, 7.6, 1.8, Dark, Seed);
            Panel (T, C, F, S, X, 0.32, 7.6, 8.1, 1.2, Dark, Seed);
            Block (0.45, X + 3.2, 0.15, 0.55, 0.6, 9.6);   --  the pier between
         end;
      end loop;
      --  the loggia: dark behind, paired columns, busts in round windows
      for K in -4 .. 4 loop
         declare
            X : constant Long_Float := Long_Float (K) * 5.9;
         begin
            for D of Long_Float_List'(-0.6, 0.6) loop
               Block (1.4, X + D, 0.45, 0.45, 10.4, 10.9);
               Frustum (T, U, V, At_P (1.4, X + D), 0.36, 0.36, 10.9, At_P (1.4, X + D), 0.3, 0.3, 19.7,
                        Mat_Stone, Seed, False);
               Block (1.4, X + D, 0.5, 0.5, 19.7, 20.4);
            end loop;
            if K < 4 then
               Panel (T, C, F, S, X + 2.95, 0.32, 11.0, 17.4, 1.7, Dark, Seed);
               Panel (T, C, F, S, X + 2.95, 0.32, 18.0, 19.6, 0.8, Dark, Seed);
               Block (0.6, X + 2.95, 0.3, 0.32, 18.2, 19.3, Mat_Gilt);   --  a bust
            end if;
         end;
      end loop;
      --  gilded masks along the attic
      for K in -8 .. 8 loop
         Block (0.45, Long_Float (K) * 3.0, 0.15, 0.4, 23.6, 24.6, Mat_Gilt);
         Block (0.4, Long_Float (K) * 3.0 + 1.5, 0.12, 0.25, 28.3, 29.6, Mat_Gilt);   --  and garlands above
      end loop;
      --  the gilded groups on the corners
      for Side_Off of Long_Float_List'(-1.0, 1.0) loop
         Block (0.0, Side_Off * (Half - 2.5), 1.8, 2.0, 31.4, 32.4);
         Gilt_Group (T, At_P (0.0, Side_Off * (Half - 2.5)), F, S, 32.4, Seed);
      end loop;
   end Opera_Front;

   --  Apollo raising his golden lyre, on the ridge of the Opéra's stage
   procedure Opera_Apollo (C : P2; Facing_Deg, Y : Long_Float) is
      T    : Tile_Builder renames Tile_At (C).all;
      A    : constant Long_Float := Facing_Deg * Ada.Numerics.Pi / 180.0;
      F    : constant V3 := (Cos (A), 0.0, Sin (A));
      S    : constant V3 := (-Sin (A), 0.0, Cos (A));
      Up   : constant V3 := (0.0, 1.0, 0.0);
      B    : constant V3 := (C.X, Y, C.Z);
      Seed : constant Long_Float := 0.5;
   begin
      Any_Box (T, B + 0.3 * Up, F, Up, Cross (F, Up), 1.0, 0.3, 1.0, Mat_Gilt, Seed);
      Any_Box (T, B + 1.9 * Up, F, Up, Cross (F, Up), 0.35, 1.3, 0.45, Mat_Gilt, Seed);
      Any_Box (T, B + 3.5 * Up, F, Up, Cross (F, Up), 0.2, 0.3, 0.2, Mat_Gilt, Seed);
      for Side_Off of Long_Float_List'(-1.0, 1.0) loop
         Beam (T, B + 3.9 * Up + (Side_Off * 0.55) * S, Normalize (Up + (Side_Off * 0.25) * S), F,
               0.8, 0.08, 0.08, Mat_Gilt, Seed);
      end loop;
      --  the lyre, held up high
      Any_Box (T, B + 5.3 * Up, S, Up, Cross (S, Up), 0.7, 0.8, 0.08, Mat_Gilt, Seed);
      Any_Box (T, B + 6.2 * Up, S, Up, Cross (S, Up), 0.9, 0.12, 0.1, Mat_Gilt, Seed);
   end Opera_Apollo;

   --  The middle of the Hôtel de Ville's west front, before its OSM wall:
   --  three storeys of tall windows between pilasters, statues in niches,
   --  three arched doors, and the projecting central pavilion with the
   --  clock and the belfry above it
   procedure Town_Hall_Front (C : P2; Facing_Deg, Half : Long_Float) is
      T    : Tile_Builder renames Tile_At (C).all;
      A    : constant Long_Float := Facing_Deg * Ada.Numerics.Pi / 180.0;
      U    : constant P2 := (Cos (A), Sin (A));
      V    : constant P2 := (-Sin (A), Cos (A));
      F    : constant V3 := (U.X, 0.0, U.Z);
      S    : constant V3 := (V.X, 0.0, V.Z);
      Seed : constant Long_Float := 0.6;
      Dark : constant Long_Float := Mat_Glass_Pane;
      Top  : constant Long_Float := 17.5;
      Mid  : constant Long_Float := 7.0;   --  half width of the central pavilion
      function At_P (Out_Off, Side_Off : Long_Float) return P2 is (C + Out_Off * U + Side_Off * V);
      procedure Block (Out_Off, Side_Off, HU, HV, Y0, Y1 : Long_Float; Mat : Long_Float := Mat_Stone) is
      begin
         Frustum (T, U, V, At_P (Out_Off, Side_Off), HU, HV, Y0, At_P (Out_Off, Side_Off), HU, HV, Y1, Mat, Seed,
                  True);
      end Block;
      procedure Statue (Out_Off, Side_Off, Y : Long_Float) is
      begin
         Block (Out_Off + 0.2, Side_Off, 0.25, 0.4, Y, Y + 0.3);
         Block (Out_Off + 0.2, Side_Off, 0.2, 0.26, Y + 0.3, Y + 1.6);
         Block (Out_Off + 0.2, Side_Off, 0.13, 0.12, Y + 1.6, Y + 1.95);
      end Statue;
      procedure Bays (From, To, Out_Off : Long_Float) is
         N : constant Natural := Natural (Long_Float'Floor ((To - From) / 4.4));
         W : constant Long_Float := (To - From) / Long_Float (Natural'Max (1, N));
      begin
         for K in 0 .. N - 1 loop
            declare
               X : constant Long_Float := From + (Long_Float (K) + 0.5) * W;
            begin
               --  windows on three floors, a dormer-like top on the last
               Panel (T, C, F, S, X, Out_Off + 0.32, 1.0, 4.4, 0.8, Dark, Seed);
               Panel (T, C, F, S, X, Out_Off + 0.32, 6.4, 9.4, 0.8, Dark, Seed);
               Panel (T, C, F, S, X, Out_Off + 0.32, 11.4, 14.2, 0.75, Dark, Seed);
               Block (Out_Off + 0.4, X, 0.12, 1.05, 9.4, 9.8);
               Block (Out_Off + 0.4, X, 0.12, 1.0, 14.2, 14.6);
               --  pilasters, and statues in the niches between every other bay
               Block (Out_Off + 0.4, X - W / 2.0, 0.12, 0.35, 0.0, Top);
               if K mod 2 = 1 then
                  Panel (T, C, F, S, X - W / 2.0, Out_Off + 0.53, 6.5, 8.9, 0.45, Dark, Seed);
                  Statue (Out_Off + 0.4, X - W / 2.0, 6.6);
                  Panel (T, C, F, S, X - W / 2.0, Out_Off + 0.53, 11.4, 13.8, 0.45, Dark, Seed);
                  Statue (Out_Off + 0.4, X - W / 2.0, 11.5);
               end if;
            end;
         end loop;
         Block (Out_Off + 0.4, To, 0.12, 0.35, 0.0, Top);
      end Bays;
   begin
      --  the face, the string courses and the cornice
      Block (0.0, 0.0, 0.3, Half, 0.0, Top);
      Block (0.25, 0.0, 0.4, Half + 0.1, 5.2, 5.7);
      Block (0.25, 0.0, 0.4, Half + 0.1, 10.3, 10.7);
      Block (0.4, 0.0, 0.7, Half + 0.3, Top, Top + 0.8);
      Bays (-Half, -Mid, 0.0);
      Bays (Mid, Half, 0.0);
      --  the central pavilion, standing forward and up
      Block (1.5, 0.0, 1.2, Mid, 0.0, 22.0);
      Block (1.9, 0.0, 1.5, Mid + 0.3, 22.0, 22.8);
      for K in -1 .. 1 loop
         declare
            X : constant Long_Float := Long_Float (K) * 4.2;
         begin
            Panel (T, C, F, S, X, 2.72, 0.0, 4.4, 1.3, Dark, Seed);     --  the doors
            Panel (T, C, F, S, X, 2.72, 4.4, 5.2, 0.9, Dark, Seed);
            Panel (T, C, F, S, X, 2.72, 6.4, 9.4, 0.85, Dark, Seed);
            Panel (T, C, F, S, X, 2.72, 11.4, 14.2, 0.8, Dark, Seed);
         end;
      end loop;
      for K in -2 .. 2 loop
         Block (2.85, Long_Float (K) * 2.1 + 1.05, 0.12, 0.3, 0.0, 15.0);
      end loop;
      Statue (2.7, -6.2, 15.6);
      Statue (2.7, 6.2, 15.6);
      --  the clock, white and lit at night, with its hands at ten to two
      declare
         Up : constant V3 := (0.0, 1.0, 0.0);
         Ctr : constant V3 := (C.X, 18.6, C.Z) + 2.75 * F;
      begin
         for K in 0 .. 7 loop
            declare
               B0 : constant Long_Float := Long_Float (K) * Ada.Numerics.Pi / 4.0;
               B1 : constant Long_Float := Long_Float (K + 1) * Ada.Numerics.Pi / 4.0;
               P0 : constant V3 := Ctr + (1.6 * Cos (B0)) * S + (1.6 * Sin (B0)) * Up;
               P1 : constant V3 := Ctr + (1.6 * Cos (B1)) * S + (1.6 * Sin (B1)) * Up;
            begin
               Solid_Quad (T, Ctr, P1, P0, Ctr, F, 0.0, 1.0, 0.0, 1.0, Mat_Lantern, Seed);
               Solid_Quad (T, Ctr, P0, P1, Ctr, F, 0.0, 1.0, 0.0, 1.0, Mat_Lantern, Seed);
            end;
         end loop;
         Beam (T, Ctr + 0.1 * F + 0.45 * Normalize (Up + 0.6 * S), Normalize (Up + 0.6 * S), F, 0.5, 0.06, 0.02,
               Mat_Lamp_Post, Seed);
         Beam (T, Ctr + 0.1 * F + 0.6 * Normalize (Up - 0.85 * S), Normalize (Up - 0.85 * S), F, 0.65, 0.05, 0.02,
               Mat_Lamp_Post, Seed);
      end;
      --  the belfry: an arcaded lantern, a tall slate spire, a finial
      Block (0.0, 0.0, 2.6, 2.6, 22.8, 23.6);
      Block (0.0, 0.0, 2.2, 2.2, 23.6, 28.0);
      for K in -1 .. 1 loop
         Panel (T, C, F, S, Long_Float (K) * 1.3, 2.22, 24.4, 27.2, 0.4, Dark, Seed);
      end loop;
      Block (0.0, 0.0, 2.5, 2.5, 28.0, 28.6);
      Frustum (T, U, V, At_P (0.0, 0.0), 2.3, 2.3, 28.6, At_P (0.0, 0.0), 0.15, 0.15, 36.0, Mat_Mansard, Seed, True);
      Frustum (T, U, V, At_P (0.0, 0.0), 0.08, 0.08, 36.0, At_P (0.0, 0.0), 0.04, 0.04, 38.5, Mat_Gilt, Seed, True);
   end Town_Hall_Front;

   --  Liberty Enlightening the World, after Bartholdi: the robe, the
   --  tablet held on the left arm, the crowned head, the right arm raised
   --  with the torch and its gilded flame; on a stone pedestal of the
   --  given height.  H: the statue, from her feet to the flame.
   procedure Liberty (C : P2; Facing_Deg, H, Plinth : Long_Float) is
      T    : Tile_Builder renames Tile_At (C).all;
      A    : constant Long_Float := Facing_Deg * Ada.Numerics.Pi / 180.0;
      U    : constant P2 := (Cos (A), Sin (A));
      V    : constant P2 := (-Sin (A), Cos (A));
      F    : constant V3 := (U.X, 0.0, U.Z);
      Up   : constant V3 := (0.0, 1.0, 0.0);
      R    : constant V3 := Cross (F, Up);   --  her right
      Seed : constant Long_Float := 0.7;
      B    : constant V3 := (C.X, Plinth, C.Z);   --  her feet
      function P (Fw, Rt, Y : Long_Float) return V3 is (B + (Fw * H) * F + (Rt * H) * R + (Y * H) * Up);
      procedure Block (Ctr : P2; HU, HV, Y0, Y1 : Long_Float; Mat : Long_Float := Mat_Stone) is
      begin
         Frustum (T, U, V, Ctr, HU, HV, Y0, Ctr, HU, HV, Y1, Mat, Seed, True);
      end Block;
      --  something round-ish: two frustums, the second turned by 45 degrees
      procedure Round (Ctr : V3; R0, R1, Y0, Y1 : Long_Float; Mat : Long_Float) is
         Q  : constant P2 := (Ctr.X, Ctr.Z);
         U2 : constant P2 := (0.7071 * (U.X - V.X), 0.7071 * (U.Z - V.Z));
         V2 : constant P2 := (-U2.Z, U2.X);
      begin
         Frustum (T, U, V, Q, R0, R0, Y0, Q, R1, R1, Y1, Mat, Seed, True);
         Frustum (T, U2, V2, Q, R0, R0, Y0, Q, R1, R1, Y1, Mat, Seed, True);
      end Round;
      PW : constant Long_Float := Long_Float'Max (0.6, 0.24 * H);   --  half width of the pedestal
   begin
      --  the pedestal: a base, the shaft, a cornice, a smaller top
      if Plinth > 0.0 then
         Block (C, PW + 0.25 * PW, PW + 0.25 * PW, 0.0, 0.12 * Plinth);
         Block (C, PW, PW, 0.12 * Plinth, 0.82 * Plinth);
         Block (C, PW + 0.12 * PW, PW + 0.12 * PW, 0.82 * Plinth, 0.88 * Plinth);
         Block (C, 0.8 * PW, 0.8 * PW, 0.88 * Plinth, Plinth);
         declare
            E : constant Long_Float := 1.25 * PW;
         begin
            Add_Edge (C + E * U + E * V, C - E * U + E * V, 0.0, Plinth);
            Add_Edge (C - E * U + E * V, C - E * U - E * V, 0.0, Plinth);
            Add_Edge (C - E * U - E * V, C + E * U - E * V, 0.0, Plinth);
            Add_Edge (C + E * U - E * V, C + E * U + E * V, 0.0, Plinth);
         end;
      end if;
      --  the robe, falling to her feet, a little wider below
      Round (B, 0.11 * H, 0.075 * H, Plinth, Plinth + 0.5 * H, Mat_Verdigris);
      Round (B + (0.01 * H) * F, 0.078 * H, 0.068 * H, Plinth + 0.5 * H, Plinth + 0.6 * H, Mat_Verdigris);
      --  the shoulders and the head, the crown with its seven rays
      Any_Box (T, P (0.0, 0.0, 0.625), F, Up, R, 0.045 * H, 0.03 * H, 0.085 * H, Mat_Verdigris, Seed);
      Round (P (0.0, 0.0, 0.0), 0.022 * H, 0.02 * H, Plinth + 0.655 * H, Plinth + 0.68 * H, Mat_Verdigris);
      Round (P (0.005, 0.0, 0.0), 0.034 * H, 0.03 * H, Plinth + 0.68 * H, Plinth + 0.735 * H, Mat_Verdigris);
      Round (P (0.0, 0.0, 0.0), 0.038 * H, 0.036 * H, Plinth + 0.73 * H, Plinth + 0.745 * H, Mat_Verdigris);
      for K in -3 .. 3 loop
         declare
            Ang : constant Long_Float := Long_Float (K) * 0.42;
            D   : constant V3 := Normalize (Cos (Ang) * F + Sin (Ang) * R + 0.35 * Up);
         begin
            Beam (T, P (0.0, 0.0, 0.74) + (0.055 * H) * D, D, Up, 0.03 * H, 0.006 * H, 0.004 * H,
                  Mat_Verdigris, Seed);
         end;
      end loop;
      --  the left arm bent, holding the tablet against her side
      Beam (T, P (0.0, -0.075, 0.57), Normalize (Up - 0.2 * R), F, 0.05 * H, 0.016 * H, 0.016 * H,
            Mat_Verdigris, Seed);
      Any_Box (T, P (0.03, -0.085, 0.53), Normalize (F + 0.3 * R), Normalize (Up + 0.35 * F),
               Cross (Normalize (F + 0.3 * R), Normalize (Up + 0.35 * F)), 0.012 * H, 0.075 * H, 0.04 * H,
               Mat_Verdigris, Seed);
      --  the right arm raised high, a little forward and out, the torch
      declare
         Sh   : constant V3 := P (0.0, 0.07, 0.635);
         D    : constant V3 := Normalize (Up + 0.12 * F + 0.18 * R);
         Hand : constant V3 := Sh + (0.24 * H) * D;
      begin
         Beam (T, Sh + (0.12 * H) * D, D, F, 0.12 * H, 0.017 * H, 0.017 * H, Mat_Verdigris, Seed);
         Beam (T, Hand + (0.03 * H) * Up, Up, F, 0.04 * H, 0.012 * H, 0.012 * H, Mat_Verdigris, Seed);
         Round (Hand + (0.07 * H) * Up, 0.012 * H, 0.03 * H, Hand.Y + 0.06 * H, Hand.Y + 0.085 * H, Mat_Verdigris);
         Round (Hand + (0.09 * H) * Up, 0.022 * H, 0.002 * H, Hand.Y + 0.085 * H, Hand.Y + 0.15 * H, Mat_Gilt);
      end;
   end Liberty;

   --  The Flame of Liberty by the Pont de l'Alma: the torch's gilded flame,
   --  full size, on a dark stone base.  H: from the ground to its tip.
   procedure Liberty_Flame (C : P2; H : Long_Float) is
      T    : Tile_Builder renames Tile_At (C).all;
      U    : constant P2 := (1.0, 0.0);
      V    : constant P2 := (0.0, 1.0);
      Seed : constant Long_Float := 0.8;
      Base : constant Long_Float := 0.45 * H;
   begin
      Frustum (T, U, V, C, 1.3, 1.3, 0.0, C, 1.3, 1.3, 0.25, Mat_Stone, Seed, True);
      Frustum (T, U, V, C, 0.85, 0.85, 0.25, C, 0.7, 0.7, Base, Mat_Lamp_Post, Seed, True);
      --  the cup of the torch, and the flame in tongues
      Frustum (T, U, V, C, 0.35, 0.35, Base, C, 0.75, 0.75, Base + 0.45, Mat_Gilt, Seed, True);
      for K in 0 .. 4 loop
         declare
            Ang : constant Long_Float := Long_Float (K) * 2.0 * Ada.Numerics.Pi / 5.0;
            D   : constant V3 := Normalize ((0.25 * Cos (Ang), 1.0, 0.25 * Sin (Ang)));
            P0  : constant V3 := (C.X + 0.25 * Cos (Ang), Base + 0.45, C.Z + 0.25 * Sin (Ang));
            L   : constant Long_Float := (H - Base - 0.45) * (if K = 0 then 1.0 else 0.75);
         begin
            Beam (T, P0 + (0.5 * L) * D, D, (-Sin (Ang), 0.0, Cos (Ang)), 0.5 * L, 0.32, 0.18, Mat_Gilt, Seed);
         end;
      end loop;
      Frustum (T, U, V, C, 0.45, 0.45, Base + 0.45, C, 0.05, 0.05, H, Mat_Gilt, Seed, True);
      Add_Edge (C + (-1.3, -1.3), C + (1.3, -1.3), 0.0, Base);
      Add_Edge (C + (1.3, -1.3), C + (1.3, 1.3), 0.0, Base);
      Add_Edge (C + (1.3, 1.3), C + (-1.3, 1.3), 0.0, Base);
      Add_Edge (C + (-1.3, 1.3), C + (-1.3, -1.3), 0.0, Base);
   end Liberty_Flame;

   procedure Emit_Hand_Landmarks (File_Name : String) is
      F : Ada.Text_IO.File_Type;
   begin
      if not Ada.Directories.Exists (File_Name) then
         return;
      end if;
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, File_Name);
      while not Ada.Text_IO.End_Of_File (F) loop
         declare
            Line : constant String := Ada.Text_IO.Get_Line (F) & " ";
            Words : array (1 .. 5) of Ada.Strings.Unbounded.Unbounded_String;
            N     : Natural := 0;
            Start : Natural := 0;
         begin
            if Line (Line'First) /= '#' then
               for I in Line'Range loop
                  if Line (I) = ' ' then
                     if Start > 0 and then N < Words'Last then
                        N := N + 1;
                        Words (N) := Ada.Strings.Unbounded.To_Unbounded_String (Line (Start .. I - 1));
                     end if;
                     Start := 0;
                  elsif Start = 0 then
                     Start := I;
                  end if;
               end loop;
            end if;
            if N = 5 then
               declare
                  use Ada.Strings.Unbounded;
                  X, Z : Long_Float;
               begin
                  Geo.To_Local (Long_Float'Value (To_String (Words (2))),
                                Long_Float'Value (To_String (Words (3))), X, Z);
                  if In_Data (X, Z) and then To_String (Words (1)) = "fountain_saint_sulpice" then
                     Fountain_Saint_Sulpice ((X, Z), Long_Float'Value (To_String (Words (4))),
                                             Long_Float'Value (To_String (Words (5))));
                     Ada.Text_IO.Put_Line ("  landmark: " & To_String (Words (1)));
                  elsif In_Data (X, Z) and then To_String (Words (1)) = "opera_front" then
                     Opera_Front ((X, Z), Long_Float'Value (To_String (Words (4))),
                                  Long_Float'Value (To_String (Words (5))));
                     Ada.Text_IO.Put_Line ("  landmark: " & To_String (Words (1)));
                  elsif In_Data (X, Z) and then To_String (Words (1)) = "opera_apollo" then
                     Opera_Apollo ((X, Z), Long_Float'Value (To_String (Words (4))),
                                   Long_Float'Value (To_String (Words (5))));
                     Ada.Text_IO.Put_Line ("  landmark: " & To_String (Words (1)));
                  elsif In_Data (X, Z) and then To_String (Words (1)) = "town_hall_front" then
                     Town_Hall_Front ((X, Z), Long_Float'Value (To_String (Words (4))),
                                      Long_Float'Value (To_String (Words (5))));
                     Ada.Text_IO.Put_Line ("  landmark: " & To_String (Words (1)));
                  elsif In_Data (X, Z) and then To_String (Words (1)) = "liberty" then
                     --  the size: the statue's height and, after a slash, the pedestal's
                     declare
                        W5 : constant String := To_String (Words (5));
                        SL : constant Natural := Ada.Strings.Fixed.Index (W5, "/");
                     begin
                        Liberty ((X, Z), Long_Float'Value (To_String (Words (4))),
                                 Long_Float'Value (W5 (W5'First .. SL - 1)),
                                 Long_Float'Value (W5 (SL + 1 .. W5'Last)));
                     end;
                     Ada.Text_IO.Put_Line ("  landmark: " & To_String (Words (1)));
                  elsif In_Data (X, Z) and then To_String (Words (1)) = "liberty_flame" then
                     Liberty_Flame ((X, Z), Long_Float'Value (To_String (Words (5))));
                     Ada.Text_IO.Put_Line ("  landmark: " & To_String (Words (1)));
                  elsif In_Data (X, Z) and then To_String (Words (1)) = "pont_pylon" then
                     Bridge_Pylon ((X, Z), Long_Float'Value (To_String (Words (4))),
                                   Long_Float'Value (To_String (Words (5))));
                     Ada.Text_IO.Put_Line ("  landmark: " & To_String (Words (1)));
                  end if;
               end;
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (F);
   end Emit_Hand_Landmarks;


   procedure Emit_Landmark (B : Building) is
      T : Tile_Builder renames Tile (Geo.Tile_Of (B.Center.X), Geo.Tile_Of (B.Center.Z)).all;
   begin
      case Landmark (B.Tags) is
         when Lattice_Tower  => Lattice_Tower_Model (T, B);
            Add_Skyline (B.Center, "tower");
         when Triumphal_Arch => Triumphal_Arch_Model (T, B);
            Add_Skyline (B.Center, "arch");
         when None           => null;
      end case;
   end Emit_Landmark;

   ---------------------------------------------------------------------------
   --  Areas, river and roads
   ---------------------------------------------------------------------------

   procedure Emit_Area (A : Area_Feature) is
      Pts  : Earcut.Point_Array (0 .. Point_Count (A.Shape) - 1);
      Tris : Earcut.Index_Vectors.Vector;
      function P (K : Natural) return P2 is
        ((Pts (Tris.Element (K)).X, Pts (Tris.Element (K)).Y));
   begin
      Triangulate (A.Shape, Pts, Tris);
      for K in 0 .. Natural (Tris.Length) / 3 - 1 loop
         Ground_Tri (A.Group, A.Mat, A.Seed, P (3 * K), P (3 * K + 1), P (3 * K + 2));
      end loop;
   end Emit_Area;

   ---------------------------------------------------------------------------
   --  Lower quays
   ---------------------------------------------------------------------------

   --  Along the Seine the paths at water level (the "ports" and the
   --  car-free Voie Georges-Pompidou) lie in a sunken band between the
   --  water and a retaining wall.  Each such way gets a strip of quads from
   --  just beyond its land-side edge to the river bank; the union of the
   --  strips is cut out of the street level and rebuilt at Low_Level.

   Bank_Edges : Ring;          --  river boundary, as point pairs
   Low_Strips : Ring;          --  4 points per quad
   Low_Boxes  : Box_Vectors.Vector;

   procedure Collect_Bank_Edges is
      procedure Add (R : Ring) is
         N : constant Natural := Natural (R.Length);
      begin
         for I in 0 .. N - 1 loop
            declare
               A : constant P2 := R (I);
               B : constant P2 := R ((I + 1) mod N);
            begin
               if Long_Float'Max (A.X, B.X) > DX0 - 100.0 and then Long_Float'Min (A.X, B.X) < DX1 + 100.0
                 and then Long_Float'Max (A.Z, B.Z) > DZ0 - 100.0 and then Long_Float'Min (A.Z, B.Z) < DZ1 + 100.0
               then
                  Bank_Edges.Append (A);
                  Bank_Edges.Append (B);
               end if;
            end;
         end loop;
      end Add;
   begin
      for P of River_Polys loop
         Add (P.Outer);
         for H of P.Holes loop
            Add (H);
         end loop;
      end loop;
   end Collect_Bank_Edges;

   --  Nearest point of the river bank to P
   procedure Nearest_Bank (P : P2; Dist_Out : out Long_Float; Q : out P2) is
      I : Natural := 0;
   begin
      Dist_Out := Long_Float'Last;
      Q := P;
      while I + 1 <= Bank_Edges.Last_Index loop
         declare
            A  : constant P2 := Bank_Edges (I);
            B  : constant P2 := Bank_Edges (I + 1);
            EX : constant Long_Float := B.X - A.X;
            EZ : constant Long_Float := B.Z - A.Z;
            L2 : constant Long_Float := EX * EX + EZ * EZ;
            T  : Long_Float := 0.0;
            C  : P2;
            D  : Long_Float;
         begin
            if abs (A.X - P.X) < Dist_Out + 300.0 then
               if L2 > 1.0E-9 then
                  T := Long_Float'Max (0.0, Long_Float'Min
                         (1.0, ((P.X - A.X) * EX + (P.Z - A.Z) * EZ) / L2));
               end if;
               C := (A.X + T * EX, A.Z + T * EZ);
               D := Dist (P, C);
               if D < Dist_Out then
                  Dist_Out := D;
                  Q := C;
               end if;
            end if;
         end;
         I := I + 2;
      end loop;
   end Nearest_Bank;

   function Point_In_Quad (P : P2; A, B, C, D : P2) return Boolean is
      R : Ring;
   begin
      R.Append (A);
      R.Append (B);
      R.Append (C);
      R.Append (D);
      return Point_In_Ring (P, R);
   end Point_In_Quad;

   function In_Low (P : P2) return Boolean is
   begin
      for K in Low_Boxes.First_Index .. Low_Boxes.Last_Index loop
         declare
            Bx : constant Box := Low_Boxes (K);
         begin
            if P.X >= Bx.X0 and then P.X <= Bx.X1 and then P.Z >= Bx.Z0
              and then P.Z <= Bx.Z1
              and then Point_In_Quad (P, Low_Strips (4 * K), Low_Strips (4 * K + 1),
                                      Low_Strips (4 * K + 2), Low_Strips (4 * K + 3))
            then
               return True;
            end if;
         end;
      end loop;
      return False;
   end In_Low;

   function Starts_With (S, Prefix : String) return Boolean is
     (S'Length >= Prefix'Length
      and then S (S'First .. S'First + Prefix'Length - 1) = Prefix);

   procedure Find_Low_Quays is
      Count : Natural := 0;
   begin
      Collect_Bank_Edges;
      if Bank_Edges.Is_Empty then
         return;
      end if;
      --  Classify point by point; ways that only partly run along the
      --  water (ramps up to the street) are split into low and high pieces
      declare
         Result : Line_Vectors.Vector;
      begin
         for L of Lines loop
            declare
               use Ada.Strings.Unbounded;
               Name  : constant String := To_String (L.Name);
               Kind  : constant String := To_String (L.Kind);
               Named : constant Boolean :=
                 Starts_With (Name, "Port ") or else Starts_With (Name, "Voie Georges")
                 or else Starts_With (Name, "Berge") or else Starts_With (Name, "Promenade");
               Path_Like : constant Boolean :=
                 One_Of (Kind, "footway|path|pedestrian|service|cycleway|track");
               Reach : constant Long_Float :=
                 (if Named or else L.Layer < 0 or else Path_Like then 30.0 else -1.0);

               function In_Port (P : P2) return Boolean is
               begin
                  for M of Marina_Polys loop
                     if Point_In_Poly (P, M) then
                        return True;
                     end if;
                  end loop;
                  return False;
               end In_Port;
               N     : constant Natural := Natural (L.Pts.Length);
               Near  : array (0 .. N - 1) of Boolean := (others => False);
               Any   : Boolean := False;
               D     : Long_Float;
               Q     : P2;
            begin
               if Reach > 0.0 and then not L.Bridge and then not Starts_With (Name, "Quai") then
                  for I in 0 .. N - 1 loop
                     Nearest_Bank (L.Pts (I), D, Q);
                     Near (I) := not In_River (L.Pts (I))
                       and then (if Named or else L.Layer < 0 or else In_Port (L.Pts (I))
                                 then D <= Reach
                                 else Name = "" and then Path_Like and then D <= 9.0);
                     Any := Any or else Near (I);
                  end loop;
               end if;
               if not Any then
                  Result.Append (L);
               else
                  --  runs of segments whose both ends are near the water
                  declare
                     Start : Natural := 0;
                     procedure Piece (First, Last : Natural; Low : Boolean) is
                        Part : Line_Feature := L;
                     begin
                        if Last <= First then
                           return;
                        end if;
                        Part.Pts.Clear;
                        Part.Ids.Clear;
                        for K in First .. Last loop
                           Part.Pts.Append (L.Pts (K));
                           Part.Ids.Append (L.Ids (K));
                        end loop;
                        Part.Low := Low;
                        if Low then
                           Part.Drive := False;
                           Count := Count + 1;
                        end if;
                        Result.Append (Part);
                     end Piece;
                     function Seg_Low (I : Natural) return Boolean is
                       (Near (I) and then Near (I + 1));
                  begin
                     for I in 1 .. N - 2 loop
                        if Seg_Low (I) /= Seg_Low (I - 1) then
                           Piece (Start, I, Seg_Low (I - 1));
                           Start := I;
                        end if;
                     end loop;
                     Piece (Start, N - 1, Seg_Low (N - 2));
                  end;
               end if;
            end;
         end loop;
         Lines := Result;
      end;

      --  Strips from the land-side edge of each low way to the water
      for L of Lines loop
         if L.Low then
            declare
               N    : constant Natural := Natural (L.Pts.Length);
               Land, Water : Ring;
            begin
               for P of L.Pts loop
                  declare
                     D  : Long_Float;
                     Q  : P2;
                     To : P2;
                  begin
                     Nearest_Bank (P, D, Q);
                     To := (if D > 0.01 then (1.0 / D) * (Q - P) else (0.0, 0.0));
                     Land.Append (P - (L.Width / 2.0 + 1.5) * To);
                     Water.Append (Q + 0.4 * To);
                  end;
               end loop;
               for I in 0 .. N - 2 loop
                  declare
                     B : Box := (Long_Float'Last, Long_Float'First,
                                 Long_Float'Last, Long_Float'First);
                     Q : constant Quad_P2 := (Land (I), Land (I + 1), Water (I + 1), Water (I));
                  begin
                     for P of Q loop
                        Low_Strips.Append (P);
                        B := (Long_Float'Min (B.X0, P.X), Long_Float'Max (B.X1, P.X),
                              Long_Float'Min (B.Z0, P.Z), Long_Float'Max (B.Z1, P.Z));
                     end loop;
                     Low_Boxes.Append (B);
                  end;
               end loop;
            end;
         end if;
      end loop;
      Ada.Text_IO.Put_Line ("  lower quay ways:" & Count'Image
                            & "  strips:" & Low_Boxes.Length'Image);
   end Find_Low_Quays;

   --  The sunken quays: street-level hole, paving below, and walls with a
   --  parapet wherever a strip borders the upper level
   --  A road (or a ramp down to the lower quays) passes here: walls and
   --  parapets along the river leave a gap for it
   type Line_Box is record
      X0, X1, Z0, Z1 : Long_Float;
   end record;
   package Road_Box_Vectors is new Ada.Containers.Vectors (Natural, Line_Box);
   Road_Boxes : Road_Box_Vectors.Vector;

   function Road_Crosses (P : P2) return Boolean is
   begin
      if Natural (Road_Boxes.Length) /= Natural (Lines.Length) then
         Road_Boxes.Clear;
         for L of Lines loop
            declare
               B : Line_Box;
            begin
               Bounds (L.Pts, B.X0, B.X1, B.Z0, B.Z1);
               Road_Boxes.Append (B);
            end;
         end loop;
      end if;
      for I in Lines.First_Index .. Lines.Last_Index loop
         declare
            L : Line_Feature renames Lines (I);
            B : Line_Box renames Road_Boxes (I);
         begin
            if L.Group = Road
              and then P.X > B.X0 - 15.0 and then P.X < B.X1 + 15.0
              and then P.Z > B.Z0 - 15.0 and then P.Z < B.Z1 + 15.0
            then
               for K in L.Pts.First_Index .. L.Pts.Last_Index - 1 loop
                  if Segment_Distance (P, L.Pts (K), L.Pts (K + 1)) < L.Width / 2.0 + 0.5 then
                     return True;
                  end if;
               end loop;
            end if;
         end;
      end loop;
      return False;
   end Road_Crosses;

   procedure Emit_Low_Quays is
   begin
      for K in Low_Boxes.First_Index .. Low_Boxes.Last_Index loop
         declare
            Q : constant Quad_P2 := (Low_Strips (4 * K), Low_Strips (4 * K + 1),
                                     Low_Strips (4 * K + 2), Low_Strips (4 * K + 3));
            Seed : constant Long_Float := 0.37;
         begin
            for Pair in 0 .. 1 loop
               declare
                  A : constant P2 := Q (0);
                  B : constant P2 := Q (1 + Pair);
                  C : constant P2 := Q (2 + Pair);
               begin
                  Ground_Tri (Hole, Mat_Water, 0.0, A, B, C);
                  Ground_Tri (Solid, Mat_Square, Seed, A, B, C, Y => Low_Level);
               end;
            end loop;

            for E in 0 .. 3 loop
               declare
                  A   : constant P2 := Q (E);
                  B   : constant P2 := Q ((E + 1) mod 4);
                  Ctr : constant P2 := 0.25 * (Q (0) + Q (1) + Q (2) + Q (3));
                  Out_N : P2 := Edge_Out (A, B);

                  function Upper_Side (P : P2) return Boolean is
                    (In_Data (P.X, P.Z)
                     and then not In_Low (P + 0.5 * Out_N)
                     and then not In_River (P + 0.5 * Out_N)
                     and then not Near_Bridge (P, 0.5)
                     and then not Road_Crosses (P));

                  procedure Wall (S, E2 : P2) is
                     T : Tile_Builder renames Tile_At (0.5 * (S + E2)).all;
                     L : constant Long_Float := Dist (S, E2);
                  begin
                     Solid_Quad (T, (S.X, Low_Level, S.Z), (E2.X, Low_Level, E2.Z),
                                 (E2.X, 0.0, E2.Z), (S.X, 0.0, S.Z),
                                 (-Out_N.X, 0.0, -Out_N.Z), 0.0, L, Low_Level, 0.0,
                                 Mat_Quay, 0.2);
                     Prism (T, Strip (S, E2, Out_N, 0.0, 0.45), 0.0, 0.95, Mat_Quay, 0.2);
                     Add_Edge (S, E2, Low_Level, 0.95);
                  end Wall;

                  procedure Walk is new Split_Runs (Upper_Side, Wall);
               begin
                  --  make Out_N point away from the strip
                  if Out_N.X * (A.X - Ctr.X) + Out_N.Z * (A.Z - Ctr.Z) < 0.0 then
                     Out_N := (-1.0) * Out_N;
                  end if;
                  if Dist (A, B) > 0.05 then
                     Walk (A, B, 1.5);
                  end if;
               end;
            end loop;
         end;
      end loop;
   end Emit_Low_Quays;

   --  The river: a hole in the street level, the water surface far below
   --  and stone quay walls with a parapet along the banks.
   procedure Emit_River (Pl : Poly) is
      Pts  : Earcut.Point_Array (0 .. Point_Count (Pl) - 1);
      Tris : Earcut.Index_Vectors.Vector;
      function P (K : Natural) return P2 is
        ((Pts (Tris.Element (K)).X, Pts (Tris.Element (K)).Y));

      procedure Bank (R : Ring) is
         N : constant Natural := Natural (R.Length);
      begin
         for I in 0 .. N - 1 loop
            declare
               A    : constant P2 := R (I);
               C    : constant P2 := R ((I + 1) mod N);
               Mid  : constant P2 := 0.5 * (A + C);
               Land : constant P2 := Edge_Out (A, C);   --  away from the water
               L    : constant Long_Float := Dist (A, C);

               Lowered : constant Boolean := In_Low (Mid + 1.0 * Land);
               Top     : constant Long_Float := (if Lowered then Low_Level else 0.0);

               function Off_Bridge (Q : P2) return Boolean is
                 (In_Data (Q.X, Q.Z) and then not Near_Bridge (Q, 2.5)
                  and then not In_Low (Q + 1.0 * Land)
                  and then not Road_Crosses (Q));

               procedure Parapet (S, E : P2) is
                  T : Tile_Builder renames Tile_At (0.5 * (S + E)).all;
               begin
                  Prism (T, Strip (S, E, Land, 0.0, 0.5), 0.0, 0.95, Mat_Quay, 0.5);
                  Add_Edge (S, E, Water_Level, 0.95);
               end Parapet;

               procedure Walk is new Split_Runs (Off_Bridge, Parapet);
            begin
               if L > 0.01 and then In_Data (Mid.X, Mid.Z) then
                  declare
                     T : Tile_Builder renames Tile_At (Mid).all;
                  begin
                     Solid_Quad (T, (A.X, Water_Level, A.Z), (C.X, Water_Level, C.Z),
                                 (C.X, Top, C.Z), (A.X, Top, A.Z),
                                 (-Land.X, 0.0, -Land.Z), 0.0, L, Water_Level, Top,
                                 Mat_Quay, 0.0);
                  end;
                  Walk (A, C, 2.0);
               end if;
            end;
         end loop;
      end Bank;
   begin
      Triangulate (Pl, Pts, Tris);
      for K in 0 .. Natural (Tris.Length) / 3 - 1 loop
         Ground_Tri (Hole, Mat_Water, 0.0, P (3 * K), P (3 * K + 1), P (3 * K + 2));
         Ground_Tri (Solid, Mat_Water, 0.0, P (3 * K), P (3 * K + 1), P (3 * K + 2),
                     Y => Water_Level);
      end loop;
      Bank (Pl.Outer);
      for H of Pl.Holes loop
         Bank (H);
      end loop;
   end Emit_River;

   --  Side of a bridge deck over the water: fascia below, parapet above
   procedure Bridge_Side (A, B, Outward : P2) is
      function Over_Water (Q : P2) return Boolean is
        (In_Data (Q.X, Q.Z) and then (In_River (Q) or else In_Low (Q))
         and then not Road_Crosses (Q));

      procedure Side (S, E : P2) is
         T : Tile_Builder renames Tile_At (0.5 * (S + E)).all;
         L : constant Long_Float := Dist (S, E);
      begin
         Solid_Quad (T, (S.X, -1.4, S.Z), (E.X, -1.4, E.Z), (E.X, 0.0, E.Z),
                     (S.X, 0.0, S.Z), (Outward.X, 0.0, Outward.Z), 0.0, L, -1.4, 0.0,
                     Mat_Quay, 0.7);
         Prism (T, Strip (S, E, Outward, -0.4, 0.4), 0.0, 1.0, Mat_Quay, 0.7);
         Add_Edge (S, E, -1.4, 1.0);
      end Side;

      procedure Walk is new Split_Runs (Over_Water, Side);
   begin
      Walk (A, B, 2.0);
   end Bridge_Side;

   procedure Emit_Bridges is
   begin
      for L of Lines loop
         if L.Bridge then
            declare
               In_Area : Boolean := False;
               Half    : constant Long_Float := L.Width / 2.0 + (if L.Curb then 0.3 else 0.0);
            begin
               for B of Bridge_Polys loop
                  if Point_In_Poly (0.5 * (L.Pts (0) + L.Pts (1)), B) then
                     In_Area := True;
                  end if;
               end loop;
               if not In_Area then
                  for I in L.Pts.First_Index .. L.Pts.Last_Index - 1 loop
                     declare
                        A : constant P2 := L.Pts (I);
                        C : constant P2 := L.Pts (I + 1);
                        Left : constant P2 := (-1.0) * Edge_Out (A, C);
                     begin
                        if Dist (A, C) > 0.01 then
                           Bridge_Side (A + Half * Left, C + Half * Left, Left);
                           Bridge_Side (A - Half * Left, C - Half * Left, (-1.0) * Left);
                        end if;
                     end;
                  end loop;
               end if;
            end;
         end if;
      end loop;
      for B of Bridge_Polys loop
         declare
            R : Ring renames B.Outer;
            N : constant Natural := Natural (R.Length);
         begin
            for I in 0 .. N - 1 loop
               declare
                  A : constant P2 := R (I);
                  C : constant P2 := R ((I + 1) mod N);
               begin
                  if Dist (A, C) > 0.01 then
                     Bridge_Side (A, C, Edge_Out (A, C));
                  end if;
               end;
            end loop;
         end;
      end loop;
   end Emit_Bridges;

   procedure Ribbon (Pts : Ring; Width : Long_Float; G : Group_Id;
                     Mat : Long_Float; Y : Long_Float := 0.0)
   is
      R     : constant Long_Float := Width / 2.0;
      Sides : constant Positive := (if Width < 3.0 then 6 else 10);
      Last  : constant Natural := Pts.Last_Index;
      Closed : constant Boolean := Pts.First_Element = Pts.Last_Element;
   begin
      for I in Pts.First_Index .. Last - 1 loop
         declare
            A  : constant P2 := Pts (I);
            B  : constant P2 := Pts (I + 1);
            Dx : constant Long_Float := B.X - A.X;
            Dz : constant Long_Float := B.Z - A.Z;
            L  : constant Long_Float := Sqrt (Dx * Dx + Dz * Dz);
            Nx, Nz : Long_Float;
         begin
            if L > 0.01 then
               Nx := -Dz / L * R;
               Nz := Dx / L * R;
               Ground_Tri (G, Mat, 0.0, (A.X + Nx, A.Z + Nz), (B.X + Nx, B.Z + Nz),
                           (B.X - Nx, B.Z - Nz), Y);
               Ground_Tri (G, Mat, 0.0, (A.X + Nx, A.Z + Nz), (B.X - Nx, B.Z - Nz),
                           (A.X - Nx, A.Z - Nz), Y);
            end if;
         end;
      end loop;
      --  Round joints and caps; nearly straight joints need none
      for I in Pts.First_Index .. Last loop
         declare
            P    : constant P2 := Pts (I);
            Need : Boolean := True;
         begin
            if (I > Pts.First_Index and then I < Last) or else (Closed and then I = Last) then
               declare
                  Prev : constant P2 := Pts (if I = Last then Last - 1 else I - 1);
                  Next : constant P2 := Pts (if I = Last then Pts.First_Index + 1 else I + 1);
                  D1   : constant P2 := P - Prev;
                  D2   : constant P2 := Next - P;
                  L1   : constant Long_Float := Sqrt (D1.X ** 2 + D1.Z ** 2);
                  L2   : constant Long_Float := Sqrt (D2.X ** 2 + D2.Z ** 2);
               begin
                  if L1 > 0.01 and then L2 > 0.01
                    and then (D1.X * D2.X + D1.Z * D2.Z) / (L1 * L2) > 0.9985
                  then
                     Need := False;
                  end if;
               end;
            elsif Closed and then I = Pts.First_Index then
               Need := False;   --  handled as the last point
            end if;
            if Need then
               for S in 0 .. Sides - 1 loop
                  declare
                     A0 : constant Long_Float := Long_Float (S) * 2.0 * Ada.Numerics.Pi / Long_Float (Sides);
                     A1 : constant Long_Float := Long_Float (S + 1) * 2.0 * Ada.Numerics.Pi / Long_Float (Sides);
                  begin
                     Ground_Tri (G, Mat, 0.0, P,
                                 (P.X + R * Cos (A0), P.Z + R * Sin (A0)),
                                 (P.X + R * Cos (A1), P.Z + R * Sin (A1)), Y);
                  end;
               end loop;
            end if;
         end;
      end loop;
   end Ribbon;

   ---------------------------------------------------------------------------
   --  Road markings
   ---------------------------------------------------------------------------

   package Use_Maps is new Ada.Containers.Hashed_Maps
     (Osm_Id, Natural, Hash_Id, "=");

   Node_Use  : Use_Maps.Map;     --  number of road ways through a node
   Crossings : Use_Maps.Map;     --  marked pedestrian crossings
   Signals   : Use_Maps.Map;     --  traffic lights: 0 both ways, 1 forward, 2 backward

   package Offset_Maps is new Ada.Containers.Hashed_Maps
     (Osm_Id, Long_Float, Hash_Id, "=");
   Signal_Offset : Offset_Maps.Map;
   --  Phase offset (s) of each signal; the lights of one junction share it

   Signal_Cycle : constant := 32.0;   --  must match shaders and Traffic

   procedure Count_Node_Use is
   begin
      for L of Lines loop
         if L.Group = Road then
            for Id of L.Ids loop
               if Node_Use.Contains (Id) then
                  Node_Use.Replace (Id, Node_Use.Element (Id) + 1);
               else
                  Node_Use.Insert (Id, 1);
               end if;
            end loop;
            --  A way's two ends both count as junction-like
            if not L.Ids.Is_Empty then
               Node_Use.Replace (L.Ids.First_Element, Node_Use.Element (L.Ids.First_Element) + 1);
               Node_Use.Replace (L.Ids.Last_Element, Node_Use.Element (L.Ids.Last_Element) + 1);
            end if;
         end if;
      end loop;
      for P of Model_Ref.Points loop
         if Tag (P.Tags, "highway") = "crossing"
           and then not One_Of (Tag (P.Tags, "crossing"), "unmarked|no|informal")
         then
            Crossings.Include (P.Id, 1);
         end if;
         if Tag (P.Tags, "highway") = "traffic_signals" then
            declare
               D : constant String := Tag (P.Tags, "traffic_signals:direction");
            begin
               Signals.Include (P.Id, (if D = "forward" then 1 elsif D = "backward" then 2 else 0));
            end;
         end if;
      end loop;

      --  Group signals less than 40 m apart into junctions (union-find)
      declare
         type Sig is record
            Id     : Osm_Id;
            Pos    : P2;
            Parent : Natural;
         end record;
         package Sig_Vectors is new Ada.Containers.Vectors (Natural, Sig);
         All_Sigs : Sig_Vectors.Vector;

         function Root (I : Natural) return Natural is
            R : Natural := I;
         begin
            while All_Sigs (R).Parent /= R loop
               R := All_Sigs (R).Parent;
            end loop;
            return R;
         end Root;
      begin
         for P of Model_Ref.Points loop
            if Signals.Contains (P.Id) then
               declare
                  X, Z : Long_Float;
               begin
                  Geo.To_Local (P.Pos.Lat, P.Pos.Lon, X, Z);
                  All_Sigs.Append ((P.Id, (X, Z), Natural (All_Sigs.Length)));
               end;
            end if;
         end loop;
         for I in All_Sigs.First_Index .. All_Sigs.Last_Index loop
            for J in I + 1 .. All_Sigs.Last_Index loop
               if abs (All_Sigs (I).Pos.X - All_Sigs (J).Pos.X) < 40.0
                 and then abs (All_Sigs (I).Pos.Z - All_Sigs (J).Pos.Z) < 40.0
                 and then Dist (All_Sigs (I).Pos, All_Sigs (J).Pos) < 40.0
               then
                  declare
                     RI : constant Natural := Root (I);
                     RJ : constant Natural := Root (J);
                  begin
                     if RI /= RJ then
                        All_Sigs (RJ).Parent := RI;
                     end if;
                  end;
               end if;
            end loop;
         end loop;
         for I in All_Sigs.First_Index .. All_Sigs.Last_Index loop
            Signal_Offset.Include
              (All_Sigs (I).Id, Signal_Cycle * Hash01 (All_Sigs (Root (I)).Id, 77));
         end loop;
      end;
   end Count_Node_Use;

   Painted_Crossings : Ring;     --  centres of zebras already painted

   procedure Paint_Rect (C : P2; Along, Across : P2; Half_Len, Half_W : Long_Float;
                         Seed : Long_Float)
   is
      P0 : constant P2 := C - Half_Len * Along - Half_W * Across;
      P1 : constant P2 := C + Half_Len * Along - Half_W * Across;
      P2v : constant P2 := C + Half_Len * Along + Half_W * Across;
      P3 : constant P2 := C - Half_Len * Along + Half_W * Across;
   begin
      Ground_Tri (Mark, Mat_Paint, Seed, P0, P1, P2v);
      Ground_Tri (Mark, Mat_Paint, Seed, P0, P2v, P3);
   end Paint_Rect;

   procedure Emit_Markings (L : Line_Feature) is
      type Real_Array is array (Natural range <>) of Long_Float;
      N     : constant Natural := Natural (L.Pts.Length);
      S     : Real_Array (0 .. N - 1);         --  arc length at each point
      Dash  : constant := 3.0;
      Gap   : constant := 7.0;
      Lanes : constant Natural := L.Lanes;

      function Blocked (At_S : Long_Float) return Boolean is
      begin
         for I in 0 .. N - 1 loop
            declare
               Id : constant Osm_Id := L.Ids (I);
               D  : constant Long_Float := abs (S (I) - At_S);
            begin
               if Node_Use.Contains (Id) and then Node_Use.Element (Id) >= 2
                 and then D < L.Width / 2.0 + 5.0
               then
                  return True;
               end if;
               if Crossings.Contains (Id) and then D < 3.2 then
                  return True;
               end if;
            end;
         end loop;
         return False;
      end Blocked;
   begin
      if L.Group /= Road or else L.Width < 5.0 or else not L.Drive then
         return;
      end if;
      S (0) := 0.0;
      for I in 1 .. N - 1 loop
         S (I) := S (I - 1) + Dist (L.Pts (I - 1), L.Pts (I));
      end loop;

      --  Lane dividers: dashed lines
      if Lanes >= 2 then
         for I in 0 .. N - 2 loop
            declare
               A     : constant P2 := L.Pts (I);
               C     : constant P2 := L.Pts (I + 1);
               Len   : constant Long_Float := S (I + 1) - S (I);
               Along : P2;
               Left  : P2;
               K0    : Integer;
            begin
               if Len > 0.5 then
                  Along := (1.0 / Len) * (C - A);
                  Left := (-Along.Z, Along.X);
                  K0 := Integer (Long_Float'Floor (S (I) / (Dash + Gap)));
                  for K in K0 .. Integer (Long_Float'Floor (S (I + 1) / (Dash + Gap))) loop
                     declare
                        D0 : constant Long_Float := Long_Float'Max (S (I), Long_Float (K) * (Dash + Gap));
                        D1 : constant Long_Float := Long_Float'Min (S (I + 1), Long_Float (K) * (Dash + Gap) + Dash);
                        Mid : constant Long_Float := 0.5 * (D0 + D1);
                     begin
                        if D1 - D0 > 0.3 and then not Blocked (Mid) then
                           for Lane in 1 .. Lanes - 1 loop
                              declare
                                 Off : constant Long_Float :=
                                   -L.Width / 2.0 + Long_Float (Lane) * L.Width / Long_Float (Lanes);
                                 Ctr : constant P2 := A + (Mid - S (I)) * Along + Off * Left;
                              begin
                                 if L.Bridge or else not In_River (Ctr) then
                                    Paint_Rect (Ctr, Along, Left, (D1 - D0) / 2.0, 0.07,
                                                Hash01 (L.Ids (I), K));
                                 end if;
                              end;
                           end loop;
                        end if;
                     end;
                  end loop;
               end if;
            end;
         end loop;
      end if;

      --  Zebra crossings at the crossing nodes of this road
      for I in 0 .. N - 1 loop
         if Crossings.Contains (L.Ids (I))
           and then (for all P of Painted_Crossings => Dist (P, L.Pts (I)) > 5.0)
         then
            Painted_Crossings.Append (L.Pts (I));
            declare
               Prev  : constant P2 := L.Pts (Natural'Max (0, I - 1));
               Next  : constant P2 := L.Pts (Natural'Min (N - 1, I + 1));
               D     : constant Long_Float := Dist (Prev, Next);
               Along : P2;
               Left  : P2;
               W     : constant Long_Float := L.Width / 2.0 - 0.3;
               Off   : Long_Float;
            begin
               if D > 0.1 then
                  Along := (1.0 / D) * (Next - Prev);
                  Left := (-Along.Z, Along.X);
                  Off := -W + 0.25;
                  while Off <= W - 0.25 loop
                     Paint_Rect (L.Pts (I) + Off * Left, Along, Left, 1.6, 0.25,
                                 Hash01 (L.Ids (I), Integer (Off * 10.0) + 500));
                     Off := Off + 1.0;
                  end loop;
               end if;
            end;
         end if;
      end loop;
   end Emit_Markings;


   ---------------------------------------------------------------------------
   --  Traffic lights
   ---------------------------------------------------------------------------

   Placed_Signals : Ring;

   --  True when P lies on the carriageway of any road (not the pavement)
   function On_Carriageway (P : P2) return Boolean is
   begin
      for L of Lines loop
         if L.Group = Road and then not L.Low then
            declare
               X0, X1, Z0, Z1 : Long_Float;
            begin
               Bounds (L.Pts, X0, X1, Z0, Z1);
               if P.X > X0 - 20.0 and then P.X < X1 + 20.0
                 and then P.Z > Z0 - 20.0 and then P.Z < Z1 + 20.0
               then
                  for I in L.Pts.First_Index .. L.Pts.Last_Index - 1 loop
                     if Segment_Distance (P, L.Pts (I), L.Pts (I + 1)) < L.Width / 2.0 + 0.3 then
                        return True;
                     end if;
                  end loop;
               end if;
            end;
         end if;
      end loop;
      return False;
   end On_Carriageway;

   --  A pole at the right-hand kerb for traffic moving along Travel, its
   --  three lamps facing the oncoming cars.  The lamps carry their phase
   --  offset and direction group (east-west or north-south) in uv, the
   --  shader and the traffic use the same timing.
   procedure Signal_Pole (Node : P2; Travel : P2; Half_Width, Offset : Long_Float;
                          Kerb : Long_Float) is
      Right  : constant P2 := (-Travel.Z, Travel.X);
      Face   : constant P2 := (-1.0) * Travel;
      Pos    : constant P2 := Node + (Half_Width + Kerb) * Right;
      Group  : constant Long_Float :=
        (if abs Travel.X >= abs Travel.Z then 0.0 else 1.0);
      T      : Tile_Builder renames Tile_At (Pos).all;
      Box_C  : constant P2 := Pos + 0.12 * Face;
      function Sq (R : Long_Float) return Quad_P2 is
        ((Pos.X - R, Pos.Z - R), (Pos.X + R, Pos.Z - R),
         (Pos.X + R, Pos.Z + R), (Pos.X - R, Pos.Z + R));
      Nrm    : constant V3 := (Face.X, 0.0, Face.Z);
   begin
      for P of Placed_Signals loop
         if Dist (P, Pos) < 1.5 then
            return;
         end if;
      end loop;
      Placed_Signals.Append (Pos);
      Prism (T, Sq (0.06), 0.0, 2.35, Mat_Lamp_Post, 0.0, Top => False);
      Prism (T, (Box_C - 0.17 * Right - 0.12 * Face, Box_C + 0.17 * Right - 0.12 * Face,
                 Box_C + 0.17 * Right + 0.12 * Face, Box_C - 0.17 * Right + 0.12 * Face),
             2.3, 3.3, Mat_Lamp_Post, 0.0);
      for K in 0 .. 2 loop
         declare
            C  : constant P2 := Box_C + 0.125 * Face;
            Y  : constant Long_Float := 3.1 - 0.3 * Long_Float (K);
            A  : constant P2 := C - 0.1 * Right;
            B  : constant P2 := C + 0.1 * Right;
         begin
            Solid_Quad (T, (A.X, Y - 0.1, A.Z), (B.X, Y - 0.1, B.Z), (B.X, Y + 0.1, B.Z),
                        (A.X, Y + 0.1, A.Z), Nrm, Offset, Offset, Group, Group,
                        Mat_Signal, Long_Float (K));
         end;
      end loop;
      Add_Edge (Pos + (-0.1, -0.1), Pos + (0.1, -0.1), 0.0, 3.3);
      Add_Edge (Pos + (0.1, -0.1), Pos + (0.1, 0.1), 0.0, 3.3);
      Add_Edge (Pos + (0.1, 0.1), Pos + (-0.1, 0.1), 0.0, 3.3);
      Add_Edge (Pos + (-0.1, 0.1), Pos + (-0.1, -0.1), 0.0, 3.3);
   end Signal_Pole;

   procedure Emit_Signals is
   begin
      for L of Lines loop
         if L.Drive then
            for I in L.Ids.First_Index .. L.Ids.Last_Index loop
               if Signals.Contains (L.Ids (I)) then
                  declare
                     Prev : constant P2 := L.Pts (Natural'Max (L.Pts.First_Index, I - 1));
                     Next : constant P2 := L.Pts (Natural'Min (L.Pts.Last_Index, I + 1));
                     D    : constant Long_Float := Dist (Prev, Next);
                     Dir  : P2;
                     Kind : constant Natural := Signals.Element (L.Ids (I));
                     Off  : constant Long_Float := Signal_Offset.Element (L.Ids (I));
                     Half : constant Long_Float := L.Width / 2.0 + 0.3;
                  begin
                     if D > 0.1 then
                        Dir := (1.0 / D) * (Next - Prev);
                        for Sign of Dist_Array'(1.0, -1.0) loop
                           declare
                              Travel : constant P2 := Sign * Dir;
                              Right  : constant P2 := (-Travel.Z, Travel.X);
                           begin
                              if (if Sign > 0.0 then L.Oneway >= 0 and then Kind /= 2
                                  else L.Oneway <= 0 and then Kind /= 1)
                              then
                                 --  on the pavement: step outwards until we leave
                                 --  every carriageway (signals tagged on a junction
                                 --  node would otherwise stand in the crossing road)
                                 --  (and back along the approach: a pole stands at
                                 --  the corner before the junction)
                                 Search :
                                 for Back of Dist_Array'(0.0, 3.0, 6.0, 10.0) loop
                                    for Kerb of Dist_Array'(0.6, 1.5, 2.5, 3.5) loop
                                       declare
                                          Base : constant P2 := L.Pts (I) - Back * Travel;
                                          Pos  : constant P2 := Base + (Half + Kerb) * Right;
                                       begin
                                          if not On_Carriageway (Pos) then
                                             if In_Data (Pos.X, Pos.Z) then
                                                Signal_Pole (Base, Travel, Half, Off, Kerb);
                                             end if;
                                             exit Search;
                                          end if;
                                       end;
                                    end loop;
                                 end loop Search;
                              end if;
                           end;
                        end loop;
                     end if;
                  end;
               end if;
            end loop;
         end if;
      end loop;
      Ada.Text_IO.Put_Line ("  traffic lights:" & Placed_Signals.Length'Image);
   end Emit_Signals;

   ---------------------------------------------------------------------------
   --  Street lamps
   ---------------------------------------------------------------------------

   function To_Ring (Q : Quad_P2) return Ring is
      R : Ring;
   begin
      for P of Q loop
         R.Append (P);
      end loop;
      return R;
   end To_Ring;

   procedure Emit_Lamp (X, Z : Long_Float; Wall_Mounted : Boolean;
                        Ground : Long_Float := 0.0) is
      T    : Tile_Builder renames Tile (Geo.Tile_Of (X), Geo.Tile_Of (Z)).all;
      C    : constant P2 := (X, Z);
      function Sq (R : Long_Float) return Quad_P2 is
        ((X - R, Z - R), (X + R, Z - R), (X + R, Z + R), (X - R, Z + R));
      Y0   : constant Long_Float := Ground + (if Wall_Mounted then 5.0 else 3.9);
   begin
      if not Wall_Mounted then
         Prism (T, Sq (0.07), Ground, Y0, Mat_Lamp_Post, 0.0, Top => False);
         Add_Edge (C + (-0.15, -0.15), C + (0.15, -0.15), Ground, Y0 + 0.9);
         Add_Edge (C + (0.15, -0.15), C + (0.15, 0.15), Ground, Y0 + 0.9);
         Add_Edge (C + (0.15, 0.15), C + (-0.15, 0.15), Ground, Y0 + 0.9);
         Add_Edge (C + (-0.15, 0.15), C + (-0.15, -0.15), Ground, Y0 + 0.9);
      end if;
      Prism (T, Sq (0.17), Y0, Y0 + 0.55, Mat_Lantern, 0.0, Top => False);
      Pyramid_Roof (T, To_Ring (Sq (0.24)), Y0 + 0.55, 0.3, Mat_Lamp_Post, 0.0);
      T.Lights.Append (Float (X));
      T.Lights.Append (Float (Lift_Y (X, Y0 + 0.3, Z)));
      T.Lights.Append (Float (Z));
   end Emit_Lamp;

   --  An ornate bronze candelabra (the Pont Alexandre III, the Opéra...):
   --  a stepped base, a fluted column, gilded rings, three lanterns on a
   --  cross-bar; Grand: the big ones with gilded cherubs round the column
   --  and five lanterns, on a stone pedestal
   procedure Emit_Candelabra (X, Z : Long_Float; Grand : Boolean; Ground : Long_Float := 0.0) is
      T    : Tile_Builder renames Tile (Geo.Tile_Of (X), Geo.Tile_Of (Z)).all;
      C    : constant P2 := (X, Z);
      function Sq (P : P2; R : Long_Float) return Quad_P2 is
        ((P.X - R, P.Z - R), (P.X + R, P.Z - R), (P.X + R, P.Z + R), (P.X - R, P.Z + R));
      B    : constant Long_Float := Ground + (if Grand then 1.6 else 0.0);   --  foot of the column
      Y0   : constant Long_Float := B + (if Grand then 4.4 else 3.9);       --  the lanterns
      procedure Lantern (P : P2; Y : Long_Float) is
      begin
         Prism (T, Sq (P, 0.13), Y, Y + 0.45, Mat_Lantern, 0.0, Top => False);
         Pyramid_Roof (T, To_Ring (Sq (P, 0.17)), Y + 0.45, 0.22, Mat_Lamp_Post, 0.0);
         Prism (T, Sq (P, 0.05), Y - 0.12, Y, Mat_Gilt, 0.0);
         T.Lights.Append (Float (P.X));
         T.Lights.Append (Float (Lift_Y (P.X, Y + 0.25, P.Z)));
         T.Lights.Append (Float (P.Z));
      end Lantern;
   begin
      if Grand then
         Prism (T, Sq (C, 0.75), Ground, Ground + 0.3, Mat_Stone, 0.0);
         Prism (T, Sq (C, 0.6), Ground + 0.3, B, Mat_Stone, 0.0);
         --  four cherubs about the column, arms up
         for K in 0 .. 3 loop
            declare
               D : constant P2 := (case K is when 0 => (0.32, 0.0), when 1 => (0.0, 0.32),
                                   when 2 => (-0.32, 0.0), when others => (0.0, -0.32));
            begin
               Prism (T, Sq (C + D, 0.14), B, B + 0.55, Mat_Gilt, 0.0);
               Prism (T, Sq (C + 1.05 * D, 0.1), B + 0.55, B + 0.75, Mat_Gilt, 0.0);
               Prism (T, Sq (C + 0.8 * D, 0.04), B + 0.75, B + 1.15, Mat_Gilt, 0.0);
            end;
         end loop;
      end if;
      Prism (T, Sq (C, 0.3), B, B + 0.35, Mat_Lamp_Post, 0.0);
      Prism (T, Sq (C, 0.2), B + 0.35, B + 0.9, Mat_Lamp_Post, 0.0);
      Prism (T, Sq (C, 0.24), B + 0.9, B + 1.0, Mat_Gilt, 0.0);
      Prism (T, Sq (C, 0.09), B + 1.0, Y0 - 0.25, Mat_Lamp_Post, 0.0, Top => False);
      Prism (T, Sq (C, 0.13), B + 2.4, B + 2.5, Mat_Gilt, 0.0);
      Prism (T, Sq (C, 0.14), Y0 - 0.3, Y0 - 0.2, Mat_Gilt, 0.0);
      --  the cross-bar(s) and the lanterns
      Prism (T, ((X - 0.55, Z - 0.03), (X + 0.55, Z - 0.03), (X + 0.55, Z + 0.03), (X - 0.55, Z + 0.03)),
             Y0 - 0.2, Y0 - 0.14, Mat_Lamp_Post, 0.0);
      Lantern ((X - 0.55, Z), Y0);
      Lantern ((X + 0.55, Z), Y0);
      Lantern (C, Y0 + 0.35);
      if Grand then
         Prism (T, ((X - 0.03, Z - 0.55), (X + 0.03, Z - 0.55), (X + 0.03, Z + 0.55), (X - 0.03, Z + 0.55)),
                Y0 - 0.2, Y0 - 0.14, Mat_Lamp_Post, 0.0);
         Lantern ((X, Z - 0.55), Y0);
         Lantern ((X, Z + 0.55), Y0);
      end if;
      Add_Edge (C + (-0.3, -0.3), C + (0.3, -0.3), Ground, Y0);
      Add_Edge (C + (0.3, -0.3), C + (0.3, 0.3), Ground, Y0);
      Add_Edge (C + (0.3, 0.3), C + (-0.3, 0.3), Ground, Y0);
      Add_Edge (C + (-0.3, 0.3), C + (-0.3, -0.3), Ground, Y0);
   end Emit_Candelabra;

   ---------------------------------------------------------------------------
   --  Trees
   ---------------------------------------------------------------------------

   type V3_Array is array (Natural range <>) of V3;
   type Nat_Array is array (Natural range <>) of Natural;

   Sphere_Verts : V3_Array (0 .. 41);
   Sphere_Tris  : Nat_Array (0 .. 239);

   procedure Build_Sphere is
      Phi : constant Long_Float := (1.0 + Sqrt (5.0)) / 2.0;
      Ico : constant V3_Array (0 .. 11) :=
        ((-1.0, Phi, 0.0), (1.0, Phi, 0.0), (-1.0, -Phi, 0.0), (1.0, -Phi, 0.0),
         (0.0, -1.0, Phi), (0.0, 1.0, Phi), (0.0, -1.0, -Phi), (0.0, 1.0, -Phi),
         (Phi, 0.0, -1.0), (Phi, 0.0, 1.0), (-Phi, 0.0, -1.0), (-Phi, 0.0, 1.0));
      Faces : constant Nat_Array (0 .. 59) :=
        (0, 11, 5,  0, 5, 1,  0, 1, 7,  0, 7, 10,  0, 10, 11,
         1, 5, 9,  5, 11, 4,  11, 10, 2,  10, 7, 6,  7, 1, 8,
         3, 9, 4,  3, 4, 2,  3, 2, 6,  3, 6, 8,  3, 8, 9,
         4, 9, 5,  2, 4, 11,  6, 2, 10,  8, 6, 7,  9, 8, 1);
      Count : Natural := 0;
      T     : Natural := 0;

      function Find_Or_Add (P : V3) return Natural is
         Q : constant V3 := Normalize (P);
      begin
         for I in 0 .. Count - 1 loop
            if abs (Sphere_Verts (I).X - Q.X) < 1.0E-9
              and then abs (Sphere_Verts (I).Y - Q.Y) < 1.0E-9
              and then abs (Sphere_Verts (I).Z - Q.Z) < 1.0E-9
            then
               return I;
            end if;
         end loop;
         Sphere_Verts (Count) := Q;
         Count := Count + 1;
         return Count - 1;
      end Find_Or_Add;
   begin
      for F in 0 .. 19 loop
         declare
            A   : constant V3 := Ico (Faces (3 * F));
            B   : constant V3 := Ico (Faces (3 * F + 1));
            C   : constant V3 := Ico (Faces (3 * F + 2));
            IA  : constant Natural := Find_Or_Add (A);
            IB  : constant Natural := Find_Or_Add (B);
            IC  : constant Natural := Find_Or_Add (C);
            IAB : constant Natural := Find_Or_Add (0.5 * (A + B));
            IBC : constant Natural := Find_Or_Add (0.5 * (B + C));
            ICA : constant Natural := Find_Or_Add (0.5 * (C + A));
            procedure Add (X, Y, Z : Natural) is
            begin
               Sphere_Tris (T) := X;
               Sphere_Tris (T + 1) := Y;
               Sphere_Tris (T + 2) := Z;
               T := T + 3;
            end Add;
         begin
            Add (IA, IAB, ICA);
            Add (IB, IBC, IAB);
            Add (IC, ICA, IBC);
            Add (IAB, IBC, ICA);
         end;
      end loop;
   end Build_Sphere;

   procedure Emit_Tree (Id : Osm_Id; X, Z : Long_Float; Ground : Long_Float := 0.0) is
      T      : Tile_Builder renames Tile (Geo.Tile_Of (X), Geo.Tile_Of (Z)).all;
      S      : constant Long_Float := 0.8 + 0.45 * Hash01 (Id, 1);
      Seed   : constant Long_Float := Hash01 (Id, 2);
      Trunk_H : constant Long_Float := Ground + 4.5 * S;
      Crown_Y : constant Long_Float := Ground + 8.5 * S;
      Crown_R : constant Long_Float := 3.6 * S;
      Base    : Interfaces.Unsigned_32;
      Sides   : constant := 6;
   begin
      --  Trunk
      for K in 0 .. Sides - 1 loop
         declare
            A0 : constant Long_Float := Long_Float (K) * 2.0 * Ada.Numerics.Pi / Long_Float (Sides);
            A1 : constant Long_Float := Long_Float (K + 1) * 2.0 * Ada.Numerics.Pi / Long_Float (Sides);
            R  : constant Long_Float := 0.22 * S;
            N  : constant V3 := (Cos ((A0 + A1) / 2.0), 0.0, Sin ((A0 + A1) / 2.0));
         begin
            Solid_Quad
              (T, (X + R * Cos (A1), Ground, Z + R * Sin (A1)),
               (X + R * Cos (A0), Ground, Z + R * Sin (A0)),
               (X + R * Cos (A0), Trunk_H + 1.0, Z + R * Sin (A0)),
               (X + R * Cos (A1), Trunk_H + 1.0, Z + R * Sin (A1)),
               N, 0.0, 1.0, 0.0, 1.0, Mat_Trunk, Seed);
         end;
      end loop;

      --  Crown: a lumpy, slightly squashed sphere
      Base := Interfaces.Unsigned_32 (Natural (T.Verts.Length) / Floats_Per_Vertex);
      for I in Sphere_Verts'Range loop
         declare
            D : constant V3 := Sphere_Verts (I);
            J : constant Long_Float := 1.0 + 0.22 * (Hash01 (Id, 10 + I) - 0.5);
            P : constant V3 := (X + D.X * Crown_R * J,
                                Crown_Y + D.Y * Crown_R * 0.85 * J,
                                Z + D.Z * Crown_R * J);
            Dummy : constant Interfaces.Unsigned_32 :=
              Add_Vertex (T, P, D, D.X, D.Z, Mat_Crown, Seed);
         begin
            null;
         end;
      end loop;
      for K in 0 .. Sphere_Tris'Length / 3 - 1 loop
         Tri (T, Solid,
              Base + Interfaces.Unsigned_32 (Sphere_Tris (3 * K)),
              Base + Interfaces.Unsigned_32 (Sphere_Tris (3 * K + 1)),
              Base + Interfaces.Unsigned_32 (Sphere_Tris (3 * K + 2)));
      end loop;

      --  Collision: a small square around the trunk
      declare
         R : constant Float := 0.4;
         FX : constant Float := Float (X);
         FZ : constant Float := Float (Z);
         C : constant array (0 .. 4, 0 .. 1) of Float :=
           ((FX - R, FZ - R), (FX + R, FZ - R), (FX + R, FZ + R),
            (FX - R, FZ + R), (FX - R, FZ - R));
      begin
         for K in 0 .. 3 loop
            Add_Edge ((Long_Float (C (K, 0)), Long_Float (C (K, 1))),
                      (Long_Float (C (K + 1, 0)), Long_Float (C (K + 1, 1))),
                      Ground, Crown_Y + Crown_R);
         end loop;
      end;
   end Emit_Tree;

   ---------------------------------------------------------------------------
   --  Output
   ---------------------------------------------------------------------------

   function Img (I : Integer) return String is
     (if I < 0 then Integer'Image (I)
      else Integer'Image (I) (2 .. Integer'Image (I)'Last));

   procedure Write_Tiles (Out_Dir : String) is
      Count : Natural := 0;
      Bytes : Long_Long_Integer := 0;
   begin
      for TX in TX0 .. TX1 loop
         for TZ in TZ0 .. TZ1 loop
            if Grid (TX, TZ) /= null then
               declare
                  B : Tile_Builder renames Grid (TX, TZ).all;
                  D : Tile_Data;

                  function To_Array (V : Float_Vectors.Vector) return Float_Array_Access is
                     R : constant Float_Array_Access :=
                       new Float_Array (0 .. Natural (V.Length) - 1);
                  begin
                     for I in R'Range loop
                        R (I) := V (I);
                     end loop;
                     return R;
                  end To_Array;
               begin
                  B.Shared.Clear;
                  D.IX := TX;
                  D.IZ := TZ;
                  D.Vertices := To_Array (B.Verts);
                  for G in Group_Id loop
                     D.Indices (G) := new Index_Array (0 .. Natural (B.Idx (G).Length) - 1);
                     for I in D.Indices (G)'Range loop
                        D.Indices (G) (I) := B.Idx (G) (I);
                     end loop;
                     --  Ground layers are drawn front-to-back with a stencil
                     --  (first triangle wins), so store them in reverse
                     if G in Ground_Group then
                        declare
                           Idx : Index_Array renames D.Indices (G).all;
                           N   : constant Natural := Idx'Length / 3;
                        begin
                           for K in 0 .. N / 2 - 1 loop
                              for C in 0 .. 2 loop
                                 declare
                                    Tmp : constant Interfaces.Unsigned_32 := Idx (3 * K + C);
                                 begin
                                    Idx (3 * K + C) := Idx (3 * (N - 1 - K) + C);
                                    Idx (3 * (N - 1 - K) + C) := Tmp;
                                 end;
                              end loop;
                           end loop;
                        end;
                     end if;
                     Bytes := Bytes + Long_Long_Integer (D.Indices (G)'Length) * 4;
                  end loop;
                  D.Edges := To_Array (B.Edges);
                  D.Lights := To_Array (B.Lights);
                  D.Roads := To_Array (B.Roads);
                  Bytes := Bytes + Long_Long_Integer (D.Vertices'Length) * 4;
                  Write (Out_Dir, D);
                  Free (D);
                  Count := Count + 1;
               end;
            end if;
         end loop;
      end loop;
      Ada.Text_IO.Put_Line ("Wrote" & Count'Image & " tiles ("
                            & Img (Integer (Bytes / 1_000_000)) & " MB) to " & Out_Dir);

   end Write_Tiles;

   --  The drivable road network for traffic, as one small file:
   --    "PRD4", node count, (OSM id, x, z, signal offset or -1) per node,
   --    way count, per way: OSM id, oneway, lanes, width, point count, node
   --    indices, name length, name (UTF-8)
   --  Every chunk writes its own file; the game merges them by OSM id.
   procedure Write_Roads (File_Name : String) is
      use Ada.Streams.Stream_IO;
      use Interfaces;
      Index : Use_Maps.Map;
      Pos   : Ring;
      Ids   : Id_Lists.Vector;
      F     : File_Type;
      S     : Stream_Access;
      Ways  : Natural := 0;
   begin
      for L of Lines loop
         if L.Drive then
            Ways := Ways + 1;
            for I in L.Ids.First_Index .. L.Ids.Last_Index loop
               if not Index.Contains (L.Ids (I)) then
                  Index.Insert (L.Ids (I), Natural (Pos.Length));
                  Pos.Append (L.Pts (I));
                  Ids.Append (L.Ids (I));
               end if;
            end loop;
         end if;
      end loop;
      Create (F, Out_File, File_Name);
      S := Stream (F);
      String'Write (S, "PRD5");
      Integer_32'Write (S, Integer_32 (Pos.Length));
      for I in Pos.First_Index .. Pos.Last_Index loop
         Integer_64'Write (S, Integer_64 (Ids.Element (I)));
         Float'Write (S, Float (Pos (I).X));
         Float'Write (S, Float (Pos (I).Z));
         declare
            Offset : Float := -1.0;
         begin
            if Signal_Offset.Contains (Ids (I)) then
               Offset := Float (Signal_Offset.Element (Ids (I)));
            end if;
            Float'Write (S, Offset);
         end;
      end loop;
      Integer_32'Write (S, Integer_32 (Ways));
      for L of Lines loop
         if L.Drive then
            Integer_64'Write (S, Integer_64 (L.Way_Id));
            Integer_32'Write (S, Integer_32 (L.Oneway));
            Integer_32'Write (S, Integer_32 (L.Lanes));
            Float'Write (S, Float (L.Width));
            Integer_32'Write (S, Integer_32 (L.Limit));
            Integer_32'Write (S, Integer_32 (L.Ids.Length));
            for Id of L.Ids loop
               Integer_32'Write (S, Integer_32 (Index.Element (Id)));
            end loop;
            declare
               Name : constant String := Ada.Strings.Unbounded.To_String (L.Name);
            begin
               Integer_32'Write (S, Integer_32 (Name'Length));
               String'Write (S, Name);
            end;
         end if;
      end loop;
      Close (F);
      Ada.Text_IO.Put_Line ("Road network:" & Pos.Length'Image & " nodes,"
                            & Ways'Image & " ways");
   end Write_Roads;

   procedure Build_Rect
     (M          : Osm_Model.Model;
      X0, X1, Z0, Z1 : Long_Float;
      Out_Dir    : String;
      Roads_File : String)
   is
      Area_Count : Natural;
      Lamps      : Natural := 0;
   begin
      Model_Ref := M'Unrestricted_Access;
      Terrain.Load;
      Output_Dir := Ada.Strings.Unbounded.To_Unbounded_String (Out_Dir);
      Read_Home ("data/home/home.txt");
      DX0 := X0;
      DX1 := X1;
      DZ0 := Z0;
      DZ1 := Z1;
      TX0 := Geo.Tile_Of (DX0);
      TX1 := Geo.Tile_Of (DX1 - 0.001);
      TZ0 := Geo.Tile_Of (DZ0);
      TZ1 := Geo.Tile_Of (DZ1 - 0.001);
      Grid := new Tile_Grid (TX0 .. TX1, TZ0 .. TZ1);
      Build_Sphere;

      Collect_Features;
      Split_Home;
      Index_Buildings;
      Count_Node_Use;
      for R of River_Polys loop
         declare
            B : Box;
         begin
            Bounds (R.Outer, B.X0, B.X1, B.Z0, B.Z1);
            River_Boxes.Append (B);
         end;
      end loop;
      Find_Low_Quays;
      Ada.Text_IO.Put_Line
        ("Buildings:" & Buildings.Length'Image & "  areas:" & Areas.Length'Image
         & "  lines:" & Lines.Length'Image & "  river parts:" & River_Polys.Length'Image
         & "  bridges:" & Bridge_Polys.Length'Image);

      --  Base pavement covering each tile
      for TX in TX0 .. TX1 loop
         for TZ in TZ0 .. TZ1 loop
            declare
               X0 : constant Long_Float := Long_Float'Max (DX0, Long_Float (TX) * Geo.Tile_Size);
               X1 : constant Long_Float := Long_Float'Min (DX1, Long_Float (TX + 1) * Geo.Tile_Size);
               Z0 : constant Long_Float := Long_Float'Max (DZ0, Long_Float (TZ) * Geo.Tile_Size);
               Z1 : constant Long_Float := Long_Float'Min (DZ1, Long_Float (TZ + 1) * Geo.Tile_Size);
            begin
               Ground_Tri (Base, Mat_Pavement, 0.0, (X0, Z0), (X1, Z0), (X1, Z1));
               Ground_Tri (Base, Mat_Pavement, 0.0, (X0, Z0), (X1, Z1), (X0, Z1));
            end;
         end loop;
      end loop;

      --  Areas, largest first so smaller ones paint over them
      Area_Count := Natural (Areas.Length);
      declare
         type Order_Array is array (Natural range <>) of Natural;
         Order : Order_Array (0 .. Area_Count - 1);
         function Less (A, B : Natural) return Boolean is
           (Areas (A).Size > Areas (B).Size);
         procedure Sort is new Ada.Containers.Generic_Array_Sort
           (Natural, Natural, Order_Array, Less);
      begin
         for I in Order'Range loop
            Order (I) := I;
         end loop;
         Sort (Order);
         for I of Order loop
            Emit_Area (Areas (I));
         end loop;
      end;
      Ada.Text_IO.Put_Line ("  areas done");

      for R of River_Polys loop
         Emit_River (R);
      end loop;
      Emit_Low_Quays;
      Ada.Text_IO.Put_Line ("  river done");

      for L of Lines loop
         declare
            G : constant Group_Id := (if L.Bridge then Deck else L.Group);
         begin
            if L.Low then
               Ribbon (L.Pts, L.Width, Solid, L.Mat, Low_Level + 0.03);
            else
               if L.Curb then
                  Ribbon (L.Pts, L.Width + 0.6, (if L.Bridge then Deck else Curb), Mat_Curb);
               end if;
               Ribbon (L.Pts, L.Width, G, L.Mat);
            end if;
         end;
      end loop;
      Emit_Bridges;
      for L of Lines loop
         Emit_Markings (L);
         --  Carriageway strips, so the game knows road from sidewalk
         if L.Group = Road and then not L.Low then
            for I in L.Pts.First_Index .. L.Pts.Last_Index - 1 loop
               declare
                  A : constant P2 := L.Pts (I);
                  C : constant P2 := L.Pts (I + 1);
               begin
                  if Touches_Data (L.Pts) then
                     declare
                        R : constant Long_Float := L.Width / 2.0 + 0.3;
                     begin
                        for TX in Integer'Max (TX0, Geo.Tile_Of (Long_Float'Min (A.X, C.X) - R))
                               .. Integer'Min (TX1, Geo.Tile_Of (Long_Float'Max (A.X, C.X) + R))
                        loop
                           for TZ in Integer'Max (TZ0, Geo.Tile_Of (Long_Float'Min (A.Z, C.Z) - R))
                                  .. Integer'Min (TZ1, Geo.Tile_Of (Long_Float'Max (A.Z, C.Z) + R))
                           loop
                              declare
                                 T : Tile_Builder renames Tile (TX, TZ).all;
                              begin
                                 T.Roads.Append (Float (A.X));
                                 T.Roads.Append (Float (A.Z));
                                 T.Roads.Append (Float (C.X));
                                 T.Roads.Append (Float (C.Z));
                                 T.Roads.Append (Float (R));
                              end;
                           end loop;
                        end loop;
                     end;
                  end if;
               end;
            end loop;
         end if;
      end loop;
      Emit_Signals;
      Ada.Text_IO.Put_Line ("  roads done");

      Read_Hand_Spots ("data/landmarks.txt");
      for I in Buildings.First_Index .. Buildings.Last_Index loop
         if In_Spot ("pont_pylon", Buildings (I).Center.X, Buildings (I).Center.Z, 1.5) then
            Buildings (I).Skip := True;   --  we build it ourselves
         end if;
      end loop;
      for I in Buildings.First_Index .. Buildings.Last_Index loop
         if Buildings (I).Skip then
            null;
         elsif Landmark (Buildings (I).Tags) /= None and then not Buildings (I).Edge_Only then
            Stand_On (Buildings (I).Shape.Outer);
            Emit_Landmark (Buildings (I));
            Follow_Ground;
         elsif Buildings (I).Is_Part or else not Buildings (I).Has_Parts then
            Stand_On (Buildings (I).Shape.Outer);
            Emit_Building (I);
            Follow_Ground;
         end if;
      end loop;
      Ada.Text_IO.Put_Line ("  buildings done");
      Emit_Hand_Landmarks ("data/landmarks.txt");

      for P of Model_Ref.Points loop
         declare
            X, Z : Long_Float;
            Kind : constant String :=
              (if Tag (P.Tags, "natural") = "tree" then "tree"
               elsif Tag (P.Tags, "highway") = "street_lamp" then "lamp"
               else "");
         begin
            if Kind /= "" then
               Geo.To_Local (P.Pos.Lat, P.Pos.Lon, X, Z);
               if In_Data (X, Z) and then not In_River ((X, Z)) then
                  if Kind = "tree" then
                     Emit_Tree (P.Id, X, Z, (if In_Low ((X, Z)) then Low_Level else 0.0));
                  elsif In_Spot ("ornate_lamps", X, Z)
                    and then Tag (P.Tags, "support") /= "wall_mounted"
                  then
                     Emit_Candelabra (X, Z, Grand => Tag (P.Tags, "tourism") = "artwork",
                                      Ground => (if In_Low ((X, Z)) then Low_Level else 0.0));
                     Lamps := Lamps + 1;
                  else
                     Emit_Lamp (X, Z, Tag (P.Tags, "support") = "wall_mounted"
                                or else Tag (P.Tags, "lamp_mount") = "wall",
                                (if In_Low ((X, Z)) then Low_Level else 0.0));
                     Lamps := Lamps + 1;
                  end if;
               end if;
            end if;
         end;
      end loop;
      Ada.Text_IO.Put_Line ("  street lamps:" & Lamps'Image);

      Write_Tiles (Out_Dir);
      Write_Roads (Out_Dir & "/" & Roads_File);
      --  The addresses (street, house number, where) for the GPS search
      declare
         F : Ada.Text_IO.File_Type;
         Count : Natural := 0;
         procedure Put (Tags : Tag_Maps.Map; X, Z : Long_Float) is
         begin
            --  (the street may be missing: the game takes the nearest one)
            if Has (Tags, "addr:housenumber")
              and then X >= DX0 and then X < DX1 and then Z >= DZ0 and then Z < DZ1
            then
               Ada.Text_IO.Put_Line
                 (F, Tag (Tags, "addr:street") & ASCII.HT & Tag (Tags, "addr:housenumber") & ASCII.HT
                  & Integer'Image (Integer (X)) & ASCII.HT & Integer'Image (Integer (Z)));
               Count := Count + 1;
            end if;
         end Put;
      begin
         Ada.Text_IO.Create (F, Ada.Text_IO.Out_File,
                             Out_Dir & "/addresses_" & Roads_File (Roads_File'First + 6 .. Roads_File'Last - 4)
                             & ".txt");
         for W of M.Ways loop
            if Has (W.Tags, "addr:housenumber") then
               declare
                  SX, SZ : Long_Float := 0.0;
                  N : Natural := 0;
               begin
                  for Id of W.Refs loop
                     declare
                        C : constant Node_Maps.Cursor := M.Nodes.Find (Id);
                        X, Z : Long_Float;
                     begin
                        if Node_Maps.Has_Element (C) then
                           Geo.To_Local (Node_Maps.Element (C).Lat, Node_Maps.Element (C).Lon, X, Z);
                           SX := SX + X;
                           SZ := SZ + Z;
                           N := N + 1;
                        end if;
                     end;
                  end loop;
                  if N > 0 then
                     Put (W.Tags, SX / Long_Float (N), SZ / Long_Float (N));
                  end if;
               end;
            end if;
         end loop;
         for P of M.Points loop
            if Has (P.Tags, "addr:housenumber") then
               declare
                  X, Z : Long_Float;
               begin
                  Geo.To_Local (P.Pos.Lat, P.Pos.Lon, X, Z);
                  Put (P.Tags, X, Z);
               end;
            end if;
         end loop;
         Ada.Text_IO.Close (F);
         Ada.Text_IO.Put_Line ("  addresses:" & Count'Image);
      end;
      --  The metro entrances (where, and which way the street runs is
      --  found in the game)
      declare
         F : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Create (F, Ada.Text_IO.Out_File,
                             Out_Dir & "/metro_" & Roads_File (Roads_File'First + 6 .. Roads_File'Last - 4)
                             & ".txt");
         for P of M.Points loop
            if Tag (P.Tags, "railway") = "subway_entrance" then
               declare
                  X, Z : Long_Float;
               begin
                  Geo.To_Local (P.Pos.Lat, P.Pos.Lon, X, Z);
                  if X >= DX0 and then X < DX1 and then Z >= DZ0 and then Z < DZ1 then
                     Ada.Text_IO.Put_Line (F, Integer'Image (Integer (X * 10.0)) & " " & Integer'Image (Integer (Z * 10.0)));
                  end if;
               end;
            end if;
         end loop;
         Ada.Text_IO.Close (F);
      end;
      declare
         F : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Create (F, Ada.Text_IO.Out_File,
                             Out_Dir & "/skyline_" & Roads_File (Roads_File'First .. Roads_File'Last - 4)
                             & ".txt");
         Ada.Text_IO.Put (F, Ada.Strings.Unbounded.To_String (Skyline));
         Ada.Text_IO.Close (F);
      end;
   end Build_Rect;

   procedure Build
     (M                         : Osm_Model.Model;
      South, West, North, East  : Long_Float;
      Out_Dir                   : String)
   is
      X0, X1, Z0, Z1 : Long_Float;
   begin
      Geo.To_Local (North, West, X0, Z0);
      Geo.To_Local (South, East, X1, Z1);
      Build_Rect (M, X0, X1, Z0, Z1, Out_Dir, "roads.bin");
   end Build;

   procedure Build_Tiles
     (M                  : Osm_Model.Model;
      TX0, TX1, TZ0, TZ1 : Integer;
      Out_Dir            : String)
   is
      function Img (I : Integer) return String is
        (Ada.Strings.Fixed.Trim (Integer'Image (I), Ada.Strings.Both));
   begin
      Build_Rect (M, Long_Float (TX0) * Geo.Tile_Size, Long_Float (TX1 + 1) * Geo.Tile_Size,
                  Long_Float (TZ0) * Geo.Tile_Size, Long_Float (TZ1 + 1) * Geo.Tile_Size,
                  Out_Dir, "roads_" & Img (TX0) & "_" & Img (TZ0) & ".bin");
   end Build_Tiles;

end World_Builder;
