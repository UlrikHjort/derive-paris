with Ada.Containers.Hashed_Maps;
with Ada.Containers.Hashed_Sets;
with Ada.Directories;
with Ada.Numerics.Elementary_Functions;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with Interfaces;

package body Road_Network is

   use Ada.Numerics.Elementary_Functions;
   use Interfaces;

   ---------------------------------------------------------------------------
   --  Spatial grid of road segments
   ---------------------------------------------------------------------------

   Cell_Size : constant := 100.0;

   type Cell_Key is record
      CX, CZ : Integer;
   end record;

   function Hash_Cell (K : Cell_Key) return Ada.Containers.Hash_Type is
     (Ada.Containers.Hash_Type ((K.CX * 73_856 + K.CZ * 19_349) mod 2**30));

   type Seg_Ref is record
      W, Pos : Natural;      --  segment Pos .. Pos + 1 of way W
   end record;

   package Seg_Vectors is new Ada.Containers.Vectors (Positive, Seg_Ref);
   package Cell_Maps is new Ada.Containers.Hashed_Maps
     (Cell_Key, Seg_Vectors.Vector, Hash_Cell, "=", Seg_Vectors."=");

   Grid : Cell_Maps.Map;

   function Cell_Of (C : Float) return Integer is
     (Integer (Float'Floor (C / Cell_Size)));

   ---------------------------------------------------------------------------
   --  Loading and merging the chunk files
   ---------------------------------------------------------------------------

   function Hash_Id (Id : Integer_64) return Ada.Containers.Hash_Type is
     (Ada.Containers.Hash_Type (Id mod 2**31));

   package Id_Maps is new Ada.Containers.Hashed_Maps
     (Integer_64, Natural, Hash_Id, "=");

   type Way_Key is record
      Id, First_Node : Integer_64;
   end record;

   function Hash_Way (K : Way_Key) return Ada.Containers.Hash_Type is
     (Ada.Containers.Hash_Type ((K.Id * 31 + K.First_Node) mod 2**31));

   package Way_Sets is new Ada.Containers.Hashed_Sets
     (Way_Key, Hash_Way, "=", "=");

   package Node_Vectors is new Ada.Containers.Vectors (Natural, Node);
   package Way_Vectors is new Ada.Containers.Vectors (Natural, Way);
   package Int_Vectors is new Ada.Containers.Vectors (Natural, Natural);

   All_Nodes  : Node_Vectors.Vector;
   All_Ways   : Way_Vectors.Vector;
   All_Points : Int_Vectors.Vector;
   Node_Index_Of : Id_Maps.Map;
   Seen_Ways  : Way_Sets.Set;

   procedure Load_File (File_Name : String) is
      use Ada.Streams.Stream_IO;
      F     : File_Type;
      S     : Stream_Access;
      Magic : String (1 .. 4);
      N     : Integer_32;
   begin
      Open (F, In_File, File_Name);
      S := Stream (F);
      String'Read (S, Magic);
      if Magic /= "PRD4" then
         Ada.Text_IO.Put_Line (File_Name & ": old format, run make tiles");
         Close (F);
         return;
      end if;

      Integer_32'Read (S, N);
      declare
         Local : array (0 .. Integer (N) - 1) of Natural;   --  file -> global
         Id    : Integer_64;
         P     : Node;
      begin
         for I in Local'Range loop
            Integer_64'Read (S, Id);
            Float'Read (S, P.X);
            Float'Read (S, P.Z);
            Float'Read (S, P.Signal);
            if Node_Index_Of.Contains (Id) then
               Local (I) := Node_Index_Of.Element (Id);
            else
               Local (I) := Natural (All_Nodes.Length);
               All_Nodes.Append (P);
               Node_Index_Of.Insert (Id, Local (I));
            end if;
         end loop;

         Integer_32'Read (S, N);
         for K in 1 .. N loop
            declare
               Way_Id       : Integer_64;
               One, Ln, Cnt : Integer_32;
               Width        : Float;
               V            : Integer_32;
            begin
               Integer_64'Read (S, Way_Id);
               Integer_32'Read (S, One);
               Integer_32'Read (S, Ln);
               Float'Read (S, Width);
               Integer_32'Read (S, Cnt);
               declare
                  Pts  : array (1 .. Integer (Cnt)) of Natural;
               begin
                  for J in Pts'Range loop
                     Integer_32'Read (S, V);
                     Pts (J) := Local (Integer (V));
                  end loop;
                  Integer_32'Read (S, V);
                  declare
                     Name : String (1 .. Natural (V));
                     Key  : Way_Key;
                  begin
                     String'Read (S, Name);
                     --  A way crossing a chunk border is in both files
                     Key := (Way_Id, (if Cnt > 0 then Integer_64 (Pts (1)) else 0));
                     if Cnt >= 2 and then not Seen_Ways.Contains (Key) then
                        Seen_Ways.Insert (Key);
                        All_Ways.Append
                          ((Oneway => Integer (One),
                            Lanes  => Positive'Max (1, Integer (Ln)),
                            Width  => Width,
                            First  => Natural (All_Points.Length),
                            Count  => Pts'Length,
                            Name   => Ada.Strings.Unbounded.To_Unbounded_String (Name)));
                        for P2 of Pts loop
                           All_Points.Append (P2);
                        end loop;
                     end if;
                  end;
               end;
            end;
         end loop;
      end;
      Close (F);
   end Load_File;

   procedure Load (Dir : String) is
      use Ada.Directories;
      Search : Search_Type;
      Item   : Directory_Entry_Type;
      Files  : Natural := 0;
   begin
      if not Exists (Dir) then
         return;
      end if;
      Start_Search (Search, Dir, "roads*.bin", (Ordinary_File => True, others => False));
      while More_Entries (Search) loop
         Get_Next_Entry (Search, Item);
         Load_File (Full_Name (Item));
         Files := Files + 1;
      end loop;
      End_Search (Search);
      if All_Ways.Is_Empty then
         Ada.Text_IO.Put_Line ("No road network in " & Dir & ": no traffic");
         return;
      end if;

      Nodes := new Node_Array (0 .. Natural (All_Nodes.Length) - 1);
      for I in Nodes'Range loop
         Nodes (I) := All_Nodes (I);
      end loop;
      Ways := new Way_Array (0 .. Natural (All_Ways.Length) - 1);
      for I in Ways'Range loop
         Ways (I) := All_Ways (I);
      end loop;
      Way_Nodes := new Int_Array (0 .. Natural (All_Points.Length) - 1);
      for I in Way_Nodes'Range loop
         Way_Nodes (I) := All_Points (I);
      end loop;
      All_Nodes.Clear;
      All_Ways.Clear;
      All_Points.Clear;
      Node_Index_Of.Clear;
      Seen_Ways.Clear;

      Links := new Link_Table (Nodes'Range);
      Walk_Links := new Link_Table (Nodes'Range);
      for W in Ways'Range loop
         for Pos in 0 .. Ways (W).Count - 1 loop
            if Pos + 1 < Ways (W).Count then
               Walk_Links (Node_Index (W, Pos)).Append ((W, Pos, 1));
               if Ways (W).Oneway >= 0 then
                  Links (Node_Index (W, Pos)).Append ((W, Pos, 1));
               end if;
            end if;
            if Pos > 0 then
               Walk_Links (Node_Index (W, Pos)).Append ((W, Pos, -1));
               if Ways (W).Oneway <= 0 then
                  Links (Node_Index (W, Pos)).Append ((W, Pos, -1));
               end if;
            end if;
         end loop;
      end loop;

      --  Every segment goes into the grid cells its bounding box touches
      for W in Ways'Range loop
         for Pos in 0 .. Ways (W).Count - 2 loop
            declare
               A : constant Node := Point (W, Pos);
               B : constant Node := Point (W, Pos + 1);
            begin
               for CX in Cell_Of (Float'Min (A.X, B.X)) .. Cell_Of (Float'Max (A.X, B.X)) loop
                  for CZ in Cell_Of (Float'Min (A.Z, B.Z)) .. Cell_Of (Float'Max (A.Z, B.Z)) loop
                     if not Grid.Contains ((CX, CZ)) then
                        Grid.Insert ((CX, CZ), Seg_Vectors.Empty_Vector);
                     end if;
                     Grid ((CX, CZ)).Append ((W, Pos));
                  end loop;
               end loop;
            end;
         end loop;
      end loop;

      Ada.Text_IO.Put_Line ("Road network:" & Nodes'Length'Image & " nodes,"
                            & Ways'Length'Image & " ways from" & Files'Image
                            & " files");
   end Load;

   ---------------------------------------------------------------------------

   procedure Segment (L : Link; A, B : out Node; Len : out Float) is
   begin
      A := Point (L.W, L.Pos);
      B := Point (L.W, L.Pos + L.Dir);
      Len := Sqrt ((B.X - A.X) ** 2 + (B.Z - A.Z) ** 2);
   end Segment;

   function Direction (L : Link) return Math3D.Vec3 is
      A, B : Node;
      Len  : Float;
   begin
      Segment (L, A, B, Len);
      if Len < 0.001 then
         return (0.0, 0.0, -1.0);
      end if;
      return ((B.X - A.X) / Len, 0.0, (B.Z - A.Z) / Len);
   end Direction;

   procedure Pick_Segment
     (X, Z, Near, Far : Float; R1, R2, R3 : Float;
      Found : out Boolean; W, Pos : out Natural)
   is
      --  a random point of the ring between Near and Far (uniform in area)
      Rad   : constant Float := Sqrt (Near * Near + R1 * (Far * Far - Near * Near));
      Angle : constant Float := R2 * 6.2831853;
      PX    : constant Float := X + Rad * Cos (Angle);
      PZ    : constant Float := Z + Rad * Sin (Angle);
      C     : constant Cell_Maps.Cursor := Grid.Find ((Cell_Of (PX), Cell_Of (PZ)));
   begin
      Found := False;
      W := 0;
      Pos := 0;
      if Cell_Maps.Has_Element (C) then
         declare
            V : constant Seg_Vectors.Vector := Cell_Maps.Element (C);
            K : constant Positive := Positive'Min
              (Natural (V.Length), 1 + Natural (Float'Floor (R3 * Float (V.Length))));
         begin
            W := V (K).W;
            Pos := V (K).Pos;
            Found := True;
         end;
      end if;
   end Pick_Segment;

   --  Closest segment to (X, Z) within Max_Distance; Named_Only skips ways
   --  without a name
   procedure Closest
     (X, Z, Max_Distance : Float; Named_Only : Boolean;
      Found : out Boolean; W, Pos : out Natural; PX, PZ : out Float)
   is
      Best : Float := Max_Distance * Max_Distance;
   begin
      Found := False;
      W := 0;
      Pos := 0;
      PX := X;
      PZ := Z;
      if not Loaded then
         return;
      end if;
      for CX in Cell_Of (X - Max_Distance) .. Cell_Of (X + Max_Distance) loop
         for CZ in Cell_Of (Z - Max_Distance) .. Cell_Of (Z + Max_Distance) loop
            declare
               C : constant Cell_Maps.Cursor := Grid.Find ((CX, CZ));
            begin
               if Cell_Maps.Has_Element (C) then
                  for S of Grid.Constant_Reference (C).Element.all loop
                     if not Named_Only
                       or else Ada.Strings.Unbounded.Length (Ways (S.W).Name) > 0
                     then
                        declare
                           A  : constant Node := Point (S.W, S.Pos);
                           B  : constant Node := Point (S.W, S.Pos + 1);
                           EX : constant Float := B.X - A.X;
                           EZ : constant Float := B.Z - A.Z;
                           L2 : constant Float := EX * EX + EZ * EZ;
                           T  : Float := 0.0;
                           D  : Float;
                        begin
                           if L2 > 1.0E-6 then
                              T := Float'Max (0.0, Float'Min
                                     (1.0, ((X - A.X) * EX + (Z - A.Z) * EZ) / L2));
                           end if;
                           D := (A.X + T * EX - X) ** 2 + (A.Z + T * EZ - Z) ** 2;
                           if D < Best then
                              Best := D;
                              Found := True;
                              W := S.W;
                              Pos := S.Pos;
                              PX := A.X + T * EX;
                              PZ := A.Z + T * EZ;
                           end if;
                        end;
                     end if;
                  end loop;
               end if;
            end;
         end loop;
      end loop;
   end Closest;

   procedure Nearest_Road
     (X, Z : Float; Found : out Boolean; PX, PZ, Heading : out Float)
   is
      W, Pos : Natural;
   begin
      Heading := 0.0;
      Closest (X, Z, 1500.0, False, Found, W, Pos, PX, PZ);
      if Found then
         declare
            A  : constant Node := Point (W, Pos);
            B  : constant Node := Point (W, Pos + 1);
         begin
            Heading := (if Ways (W).Oneway < 0 then Arctan (A.X - B.X, B.Z - A.Z)
                        else Arctan (B.X - A.X, A.Z - B.Z));
         end;
      end if;
   end Nearest_Road;

   function Street_At (X, Z : Float; Max_Distance : Float := 14.0) return String is
      Found  : Boolean;
      W, Pos : Natural;
      PX, PZ : Float;
   begin
      Closest (X, Z, Max_Distance, True, Found, W, Pos, PX, PZ);
      return (if Found then Ada.Strings.Unbounded.To_String (Ways (W).Name) else "");
   end Street_At;

   procedure For_Segments_Near (X, Z, Radius : Float) is
   begin
      if not Loaded then
         return;
      end if;
      for CX in Cell_Of (X - Radius) .. Cell_Of (X + Radius) loop
         for CZ in Cell_Of (Z - Radius) .. Cell_Of (Z + Radius) loop
            declare
               C : constant Cell_Maps.Cursor := Grid.Find ((CX, CZ));
            begin
               if Cell_Maps.Has_Element (C) then
                  for S of Grid.Constant_Reference (C).Element.all loop
                     declare
                        A : constant Node := Point (S.W, S.Pos);
                        B : constant Node := Point (S.W, S.Pos + 1);
                     begin
                        --  only from the cell holding its first point
                        if Cell_Of (A.X) = CX and then Cell_Of (A.Z) = CZ then
                           Visit (A.X, A.Z, B.X, B.Z, Ways (S.W).Width,
                                  Ada.Strings.Unbounded.Length (Ways (S.W).Name) > 0);
                        end if;
                     end;
                  end loop;
               end if;
            end;
         end loop;
      end loop;
   end For_Segments_Near;

   ---------------------------------------------------------------------------
   --  A* over the nodes; links give the allowed driving directions
   ---------------------------------------------------------------------------

   procedure Find_Route
     (From_X, From_Z, Heading, To_X, To_Z : Float;
      Route : out Route_Vectors.Vector; Found : out Boolean)
   is
      type Real_Array is array (Natural range <>) of Float;
      type Nat_Array is array (Natural range <>) of Integer;
      N     : constant Natural := Nodes'Length;
      Cost  : Real_Array (0 .. N - 1) := (others => Float'Last);
      Prev  : Nat_Array (0 .. N - 1) := (others => -1);
      Via   : Nat_Array (0 .. N - 1) := (others => -1);   --  way used to arrive
      Done  : array (0 .. N - 1) of Boolean := (others => False);

      --  binary heap of (estimate, node)
      type Entry_T is record
         F    : Float;
         Node : Natural;
      end record;
      package Heap_Vectors is new Ada.Containers.Vectors (Natural, Entry_T);
      Heap : Heap_Vectors.Vector;

      procedure Push (E : Entry_T) is
         I : Natural := Natural (Heap.Length);
      begin
         Heap.Append (E);
         while I > 0 and then Heap ((I - 1) / 2).F > Heap (I).F loop
            Heap.Swap (I, (I - 1) / 2);
            I := (I - 1) / 2;
         end loop;
      end Push;

      function Pop return Entry_T is
         Top : constant Entry_T := Heap (0);
         I   : Natural := 0;
      begin
         Heap (0) := Heap.Last_Element;
         Heap.Delete_Last;
         loop
            declare
               L : constant Natural := 2 * I + 1;
               R : constant Natural := 2 * I + 2;
               M : Natural := I;
            begin
               if L < Natural (Heap.Length) and then Heap (L).F < Heap (M).F then
                  M := L;
               end if;
               if R < Natural (Heap.Length) and then Heap (R).F < Heap (M).F then
                  M := R;
               end if;
               exit when M = I;
               Heap.Swap (I, M);
               I := M;
            end;
         end loop;
         return Top;
      end Pop;

      function H (Node_I : Natural) return Float is
        (Sqrt ((Nodes (Node_I).X - To_X) ** 2 + (Nodes (Node_I).Z - To_Z) ** 2));

      Got    : Boolean;
      SW, SP : Natural;
      PX, PZ : Float;
      GW, GP : Natural;
      GX, GZ : Float;
      Goal_A, Goal_B : Natural;
      Hx : constant Float := Sin (Heading);
      Hz : constant Float := -Cos (Heading);
      Best_Goal : Integer := -1;
   begin
      Route.Clear;
      Found := False;
      if not Loaded then
         return;
      end if;
      Closest (From_X, From_Z, 60.0, False, Got, SW, SP, PX, PZ);
      if not Got then
         return;
      end if;
      Closest (To_X, To_Z, 300.0, False, Got, GW, GP, GX, GZ);
      if not Got then
         return;
      end if;
      Goal_A := Node_Index (GW, GP);
      Goal_B := Node_Index (GW, GP + 1);

      --  start: both ends of the car's segment, where driving there is
      --  allowed; turning round costs extra
      declare
         A  : constant Node := Point (SW, SP);
         B  : constant Node := Point (SW, SP + 1);
         DX : constant Float := B.X - A.X;
         DZ : constant Float := B.Z - A.Z;
         Along : constant Boolean := DX * Hx + DZ * Hz >= 0.0;
         procedure Seed (Node_I : Natural; Dist : Float; Forward_Ok : Boolean; With_Heading : Boolean) is
            C : constant Float := Dist + (if With_Heading then 0.0 else 150.0);
         begin
            if Forward_Ok and then C < Cost (Node_I) then
               Cost (Node_I) := C;
               Via (Node_I) := SW;
               Push ((C + H (Node_I), Node_I));
            end if;
         end Seed;
      begin
         Seed (Node_Index (SW, SP + 1), Sqrt ((B.X - PX) ** 2 + (B.Z - PZ) ** 2),
               Ways (SW).Oneway >= 0, Along);
         Seed (Node_Index (SW, SP), Sqrt ((A.X - PX) ** 2 + (A.Z - PZ) ** 2),
               Ways (SW).Oneway <= 0, not Along);
      end;

      while not Heap.Is_Empty loop
         declare
            E : constant Entry_T := Pop;
            U : constant Natural := E.Node;
         begin
            if not Done (U) then
               Done (U) := True;
               if U = Goal_A or else U = Goal_B then
                  Best_Goal := U;
                  exit;
               end if;
               for L of Links (U) loop
                  declare
                     V   : constant Natural := Node_Index (L.W, L.Pos + L.Dir);
                     A   : constant Node := Nodes (U);
                     B   : constant Node := Nodes (V);
                     Len : constant Float := Sqrt ((B.X - A.X) ** 2 + (B.Z - A.Z) ** 2);
                     --  small penalty for changing street: prefer simple routes
                     C   : constant Float := Cost (U) + Len
                       + (if Via (U) >= 0 and then Via (U) /= L.W then 8.0 else 0.0);
                  begin
                     if not Done (V) and then C < Cost (V) then
                        Cost (V) := C;
                        Prev (V) := U;
                        Via (V) := L.W;
                        Push ((C + H (V), V));
                     end if;
                  end;
               end loop;
            end if;
         end;
      end loop;

      if Best_Goal < 0 then
         return;
      end if;
      --  walk back from the goal
      declare
         package Int_Vectors2 is new Ada.Containers.Vectors (Natural, Natural);
         Path : Int_Vectors2.Vector;
         K    : Integer := Best_Goal;
      begin
         while K >= 0 loop
            Path.Prepend (K);
            K := Prev (K);
         end loop;
         Route.Append ((From_X, From_Z, Via (Path.First_Element)));
         for I in Path.First_Index .. Path.Last_Index loop
            declare
               Next_Way : constant Natural :=
                 (if I < Path.Last_Index then Via (Path (I + 1)) else GW);
            begin
               Route.Append ((Nodes (Path (I)).X, Nodes (Path (I)).Z, Next_Way));
            end;
         end loop;
         Route.Append ((GX, GZ, GW));
         Found := True;
      end;
   end Find_Route;

   function Signal_State (Offset, Dir_X, Dir_Z, Time : Float) return Light is
      Phase : constant Float :=
        Time + Offset - Signal_Cycle * Float'Floor ((Time + Offset) / Signal_Cycle);
   begin
      if abs Dir_X >= abs Dir_Z then          --  east-west movement
         return (if Phase < 13.0 then Green elsif Phase < 16.0 then Amber else Red);
      else                                    --  north-south movement
         return (if Phase < 16.0 then Red elsif Phase < 29.0 then Green else Amber);
      end if;
   end Signal_State;

end Road_Network;
